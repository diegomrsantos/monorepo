// Included in coalescing::platform::paged; all items are private benchmark helpers.

use commonware_runtime::{
    Blob, Handle, IoBufsMut,
    buffer::paged::{CacheRef, Writer},
};
use std::num::NonZeroUsize;

/// Change only the buffers passed to the real runtime; forward the sync contract.
#[derive(Clone)]
struct TransformBlob {
    inner: RuntimeBlob,
    strategy: Strategy,
    pool: BufferPool,
}

impl Blob for TransformBlob {
    async fn read_at_buf(
        &self,
        offset: u64,
        len: usize,
        bufs: impl Into<IoBufsMut> + Send,
        options: ReadOptions,
    ) -> std::result::Result<IoBufsMut, commonware_runtime::Error> {
        self.inner.read_at_buf(offset, len, bufs, options).await
    }

    async fn read_at(
        &self,
        offset: u64,
        len: usize,
        options: ReadOptions,
    ) -> std::result::Result<IoBufsMut, commonware_runtime::Error> {
        self.inner.read_at(offset, len, options).await
    }

    async fn write_at(
        &self,
        offset: u64,
        bufs: impl Into<IoBufs> + Send,
        options: WriteOptions,
    ) -> std::result::Result<(), commonware_runtime::Error> {
        let bufs = bufs.into();
        let bufs = match self.strategy {
            Strategy::Vectored => bufs,
            Strategy::Coalesce => bufs.coalesce().into(),
            Strategy::Pool => bufs.coalesce_with_pool(&self.pool).into(),
        };
        self.inner.write_at(offset, bufs, options).await
    }

    async fn resize(&self, len: u64) -> std::result::Result<(), commonware_runtime::Error> {
        self.inner.resize(len).await
    }

    async fn sync(&self) -> std::result::Result<(), commonware_runtime::Error> {
        self.inner.sync().await
    }

    async fn start_sync(&self) -> Handle<()> {
        self.inner.start_sync().await
    }
}

async fn append(
    cfg: &Config,
    writer: &mut Writer<TransformBlob>,
    sources: &[(IoBuf, IoBufs)],
    ops: usize,
) -> Result<()> {
    let logical_bytes = sources[0].0.len();
    for op in 0..ops {
        let offset = writer
            .append_owned(sources[op % sources.len()].0.clone())
            .await?;
        if offset != (op * logical_bytes) as u64 {
            return Err(Error::Invalid(
                "append returned an unexpected logical offset".into(),
            ));
        }
        if cfg.durable {
            writer.sync().await?;
        }
    }
    // snapshot flushes any remaining tip to the Blob without requiring a sync.
    // Thus buffered timing includes acceptance of every appended byte by storage.
    drop(writer.snapshot().await?);
    Ok(())
}

pub(super) fn run(cfg: Config, ops_per_writer: usize) -> Result<()> {
    let physical_bytes = cfg.pages * cfg.physical_page_size as usize;
    let logical_bytes = cfg.pages * page_size(cfg.physical_page_size).get() as usize;
    let source_bytes = cfg
        .source_mib
        .checked_mul(MIB)
        .ok_or_else(|| Error::Invalid("source size overflow".into()))?;
    let source_count = source_bytes.div_ceil(logical_bytes).max(1);
    let cache_pages = 4096;
    let buffer_pages = 4;
    let root = cfg
        .root
        .join(format!("paged-coalescing-{}", std::process::id()));
    fs::create_dir(&root)?;
    let runtime_cfg = tokio::Config::default()
        .with_worker_threads(4)
        .with_storage_directory(root.clone());
    let result = tokio::Runner::new(runtime_cfg).start(|context| async move {
        let pool = context.storage_buffer_pool().clone();
        let mut workers = Vec::new();
        for index in 0..cfg.writers {
            let name = index.to_be_bytes();
            let (blob, size) = context.open("paged-measured", &name).await?;
            if size != 0 {
                return Err(Error::Invalid("measured append file is not empty".into()));
            }
            let (warmup_blob, warmup_size) = context.open("paged-warmup", &name).await?;
            let cache = CacheRef::new(
                pool.clone(),
                page_size(cfg.physical_page_size),
                NonZeroUsize::new(cache_pages).unwrap(),
            );
            let wrap = |inner| TransformBlob {
                inner,
                strategy: cfg.strategy,
                pool: pool.clone(),
            };
            let writer = Writer::new(
                wrap(blob.clone()),
                size,
                buffer_pages * page_size(cfg.physical_page_size).get() as usize,
                cache.clone(),
            )
            .await?;
            let warmup = Writer::new(
                wrap(warmup_blob),
                warmup_size,
                buffer_pages * page_size(cfg.physical_page_size).get() as usize,
                cache,
            )
            .await?;
            let mut rng = TestRng::new(cfg.seed.wrapping_add(index as u64));
            let sources = (0..source_count)
                .map(|_| payload_parts(&cfg, &mut rng))
                .collect::<Vec<_>>();
            workers.push((index, writer, warmup, blob, sources));
        }
        let ready = Arc::new(Barrier::new(cfg.writers + 1));
        let start = Arc::new(Barrier::new(cfg.writers + 1));
        let done = Arc::new(Barrier::new(cfg.writers + 1));
        let release = Arc::new(Barrier::new(cfg.writers + 1));
        let cfg = &cfg;
        let (wall, cpu, verified_pages) = thread::scope(|scope| -> Result<_> {
            let mut handles = Vec::new();
            for (index, mut writer, mut warmup, blob, sources) in workers {
                let (ready, start, done, release) =
                    (ready.clone(), start.clone(), done.clone(), release.clone());
                let handle = ::tokio::runtime::Handle::current();
                let context = &context;
                handles.push(scope.spawn(move || {
                    let warmed = handle.block_on(async {
                        append(cfg, &mut warmup, &sources, cfg.warmup_ops).await?;
                        warmup.sync().await?;
                        drop(warmup);
                        context
                            .remove("paged-warmup", Some(&index.to_be_bytes()))
                            .await?;
                        Ok::<_, Error>(())
                    });
                    ready.wait();
                    start.wait();
                    let measured = warmed.and_then(|_| {
                        handle.block_on(append(cfg, &mut writer, &sources, ops_per_writer))
                    });
                    done.wait();
                    release.wait();
                    measured?;
                    handle.block_on(writer.sync())?;
                    drop(writer);
                    // Reopen the raw Blob so neither Writer's cache nor recovery can
                    // conceal a missing page, corrupt footer, or incorrect file length.
                    let (reopened, bytes) =
                        handle.block_on(context.open("paged-measured", &index.to_be_bytes()))?;
                    if bytes != (ops_per_writer * physical_bytes) as u64 {
                        return Err(Error::Invalid(
                            "append file has an unexpected physical length".into(),
                        ));
                    }
                    drop(blob);
                    let backend = Backend::Runtime {
                        blob: reopened,
                        handle,
                    };
                    for op in 0..ops_per_writer {
                        backend.verify(
                            (op * physical_bytes) as u64,
                            &sources[op % sources.len()].1,
                            cfg.physical_page_size as usize,
                        )?;
                    }
                    Ok::<_, Error>(ops_per_writer * cfg.pages)
                }));
            }
            ready.wait();
            let cpu_start = cpu_time();
            let wall_start = Instant::now();
            start.wait();
            done.wait();
            let wall = wall_start.elapsed();
            let cpu_end = cpu_time();
            release.wait();
            let verified = handles
                .into_iter()
                .map(|h| {
                    h.join()
                        .map_err(|_| Error::Invalid("paged benchmark worker panicked".into()))?
                })
                .collect::<Result<Vec<_>>>()?
                .into_iter()
                .sum::<usize>();
            Ok((wall, cpu_end? - cpu_start?, verified))
        })?;
        let ops = ops_per_writer * cfg.writers;
        Ok::<_, Error>(json!({
            "strategy": format!("{:?}", cfg.strategy).to_lowercase(),
            "platform": std::env::consts::OS, "architecture": std::env::consts::ARCH,
            "layer": "paged", "workload": "append_owned_full_pages",
            "measurement": "fixed_completed_work", "durable": cfg.durable,
            "physical_page_size": cfg.physical_page_size,
            "logical_page_size": page_size(cfg.physical_page_size).get(),
            "pages": cfg.pages, "writers": cfg.writers,
            "bytes_per_write": logical_bytes, "physical_bytes_per_append": physical_bytes,
            "file_bytes": ops * physical_bytes, "source_count": source_count,
            "source_bytes_per_writer": source_count * logical_bytes,
            "write_buffer_pages": buffer_pages, "cache_pages_per_writer": cache_pages,
            "pool_max_size": pool.config().max_size().get(),
            "pool_size_eligible": physical_bytes <= pool.config().max_size().get(),
            "seed": cfg.seed, "warmup_ops_per_writer": cfg.warmup_ops,
            "wall_seconds": wall.as_secs_f64(), "cpu_seconds": cpu.as_secs_f64(),
            "ops": ops, "ops_per_second": ops as f64 / wall.as_secs_f64(),
            "mib_per_second": ops as f64 * logical_bytes as f64 / MIB as f64 / wall.as_secs_f64(),
            "cpu_ns_per_op": cpu.as_nanos() as f64 / ops as f64,
            "verified_pages": verified_pages,
            "verified_bytes": verified_pages * cfg.physical_page_size as usize,
            "verification": "reopened_raw_blob_all_bytes_crc_and_exact_length"
        }))
    });
    fs::remove_dir_all(&root)?;
    println!("{}", result?);
    Ok(())
}
