//! Compare fragmented and coalesced writes with the paged writer's layout of full pages.
//!
//! Payload construction and CRC computation precede timing. Every measured operation
//! includes cloning the fragment list, strategy allocation and copying, writing, and
//! dropping its buffers. Buffered runs measure acceptance into the page cache; durable
//! runs include the backend's durability policy in each operation.

#[path = "coalescing_checks.rs"]
#[cfg(any(target_os = "linux", target_os = "macos"))]
mod checks;

#[cfg(not(any(target_os = "linux", target_os = "macos")))]
fn main() {
    panic!("run this benchmark on Linux or macOS");
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
fn main() -> Result<(), platform::Error> {
    platform::main()
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
mod platform {
    use clap::{Parser, ValueEnum};
    use commonware_cryptography::Crc32;
    use commonware_runtime::{
        Blob as _, BufferPool, BufferPooler as _, IoBuf, IoBufs, ReadOptions, Runner as _,
        Storage as _, WriteOptions,
        buffer::paged::{CHECKSUM_SIZE, page_size},
        tokio::{self, Context},
    };
    use commonware_utils::TestRng;
    use rand::Rng as _;
    use serde_json::json;
    use std::{
        fs::{self, File, OpenOptions},
        io,
        os::unix::fs::FileExt,
        path::PathBuf,
        sync::{Arc, Barrier, OnceLock},
        thread,
        time::{Duration, Instant},
    };

    const MIB: usize = 1024 * 1024;
    #[cfg(target_os = "linux")]
    use commonware_runtime::Buf as _;
    #[cfg(target_os = "linux")]
    use std::{io::IoSlice, os::fd::AsRawFd};

    #[cfg(target_os = "linux")]
    const IOV_MAX: usize = 1024;
    type RuntimeBlob = <Context as commonware_runtime::Storage>::Blob;
    type Result<T> = std::result::Result<T, Error>;

    #[derive(Debug, thiserror::Error)]
    pub enum Error {
        #[error(transparent)]
        Io(#[from] io::Error),
        #[error(transparent)]
        Runtime(#[from] commonware_runtime::Error),
        #[error("{0}")]
        Invalid(String),
    }

    #[derive(Clone, Copy, Debug, ValueEnum)]
    enum Strategy {
        Vectored,
        Coalesce,
        Pool,
    }

    #[derive(Clone, Copy, Debug, ValueEnum)]
    enum Layer {
        Syscall,
        Runtime,
        Paged,
    }

    #[derive(Debug, Parser)]
    struct Config {
        #[arg(long)]
        root: PathBuf,
        #[arg(long, value_enum)]
        strategy: Strategy,
        #[arg(long, value_enum, default_value = "syscall")]
        layer: Layer,
        #[arg(long, default_value_t = 4096)]
        physical_page_size: u32,
        #[arg(long, default_value_t = 16)]
        pages: usize,
        /// Uniform fragments instead of the paged layout; requires write_bytes.
        #[arg(long, requires = "write_bytes")]
        segments: Option<usize>,
        #[arg(long, requires = "segments")]
        write_bytes: Option<usize>,
        /// Allocate each uniform fragment separately during source preparation.
        #[arg(long, requires = "segments")]
        independent_segments: bool,
        #[arg(long, default_value_t = 1)]
        writers: usize,
        #[arg(long, default_value_t = 1500)]
        duration_ms: u64,
        #[arg(long, default_value_t = 300)]
        warmup_ms: u64,
        /// Appends to a separate warmup file for the fixed work paged workload.
        #[arg(long, default_value_t = 64)]
        warmup_ops: usize,
        /// Total file space, divided among writers and rounded down to complete writes.
        #[arg(long, default_value_t = 128)]
        file_mib: usize,
        /// Rotating source bytes per writer; zero reuses one payload.
        #[arg(long, default_value_t = 0)]
        source_mib: usize,
        #[arg(long)]
        durable: bool,
        #[arg(long, default_value_t = 42)]
        seed: u64,
    }

    enum Backend {
        Syscall(File),
        Runtime {
            blob: RuntimeBlob,
            handle: ::tokio::runtime::Handle,
        },
    }

    impl Backend {
        fn write(&self, offset: u64, bufs: IoBufs, durable: bool) -> Result<()> {
            match self {
                Self::Syscall(file) => write_syscall(file, offset, bufs, durable),
                Self::Runtime { blob, handle } => {
                    let options = if durable {
                        WriteOptions::SYNC
                    } else {
                        WriteOptions::default()
                    };
                    handle.block_on(blob.write_at(offset, bufs, options))?;
                    Ok(())
                }
            }
        }

        fn sync(&self) -> Result<()> {
            match self {
                Self::Syscall(file) => file.sync_data()?,
                Self::Runtime { blob, handle } => handle.block_on(blob.sync())?,
            }
            Ok(())
        }

        fn verify(&self, offset: u64, expected: &IoBufs, physical_page: usize) -> Result<()> {
            let expected = expected.clone().coalesce();
            let actual = match self {
                Self::Syscall(file) => {
                    let mut data = vec![0u8; expected.len()];
                    file.read_exact_at(&mut data, offset)?;
                    IoBuf::from(data)
                }
                Self::Runtime { blob, handle } => handle
                    .block_on(blob.read_at(offset, expected.len(), ReadOptions::default()))?
                    .coalesce()
                    .freeze(),
            };
            if actual.as_ref() != expected.as_ref() {
                return Err(Error::Invalid(
                    "write readback differs from the source".into(),
                ));
            }
            if physical_page == 0 {
                return Ok(());
            }
            let logical = physical_page - CHECKSUM_SIZE as usize;
            for page in actual.as_ref().chunks_exact(physical_page) {
                let footer = &page[logical..];
                let len = u16::from_be_bytes(footer[..2].try_into().unwrap()) as usize;
                let crc = u32::from_be_bytes(footer[2..6].try_into().unwrap());
                if len != logical
                    || Crc32::checksum(&page[..logical]) != crc
                    || footer[6..] != [0; 6]
                {
                    return Err(Error::Invalid("invalid CRC record for a full page".into()));
                }
            }
            Ok(())
        }
    }

    /// Match the ordinary Unix backend's write strategy and durability batching.
    #[cfg(target_os = "linux")]
    fn write_syscall(file: &File, mut offset: u64, bufs: IoBufs, durable: bool) -> Result<()> {
        let mut bufs = if !durable {
            match bufs.try_into_single() {
                Ok(buf) => {
                    file.write_all_at(buf.as_ref(), offset)?;
                    return Ok(());
                }
                Err(bufs) => bufs,
            }
        } else {
            bufs
        };
        let fused = durable && bufs.chunk_count() <= IOV_MAX;
        while bufs.has_remaining() {
            let mut slices = vec![IoSlice::new(&[]); bufs.chunk_count().min(IOV_MAX)];
            let count = bufs.chunks_vectored(&mut slices);
            // SAFETY: The file and buffers outlive the call. IoSlice has the Unix
            // iovec ABI, count is bounded by the initialized slice, and the benchmark
            // validates its file size before any offset is converted to off_t.
            let written = unsafe {
                libc::pwritev2(
                    file.as_raw_fd(),
                    slices.as_ptr().cast::<libc::iovec>(),
                    count as i32,
                    offset as libc::off_t,
                    if fused { libc::RWF_DSYNC } else { 0 },
                )
            };
            if written < 0 {
                let error = io::Error::last_os_error();
                if error.kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(error.into());
            }
            if written == 0 {
                return Err(io::Error::from(io::ErrorKind::WriteZero).into());
            }
            drop(slices);
            bufs.advance(written as usize);
            offset += written as u64;
        }
        if durable && !fused {
            file.sync_data()?;
        }
        Ok(())
    }

    #[cfg(target_os = "macos")]
    fn write_syscall(_: &File, _: u64, _: IoBufs, _: bool) -> Result<()> {
        Err(Error::Invalid(
            "the syscall layer is Linux only; use runtime or paged".into(),
        ))
    }

    fn cpu_time() -> Result<Duration> {
        let mut value = libc::timespec {
            tv_sec: 0,
            tv_nsec: 0,
        };
        // SAFETY: value points to writable timespec storage for this synchronous call.
        if unsafe { libc::clock_gettime(libc::CLOCK_PROCESS_CPUTIME_ID, &mut value) } != 0 {
            return Err(io::Error::last_os_error().into());
        }
        Ok(Duration::new(value.tv_sec as u64, value.tv_nsec as u32))
    }

    /// Match Writer::append_full_pages: one payload allocation, one CRC allocation,
    /// and two borrowed slices per physical page. Source construction is not timed.
    fn payload(cfg: &Config, rng: &mut TestRng) -> IoBufs {
        payload_parts(cfg, rng).1
    }

    fn payload_parts(cfg: &Config, rng: &mut TestRng) -> (IoBuf, IoBufs) {
        if let Some(segments) = cfg.segments {
            let len = cfg.write_bytes.unwrap();
            let mut data = vec![0u8; len];
            rng.fill_bytes(&mut data);
            let data = IoBuf::from(data);
            let mut bufs = IoBufs::default();
            for segment in 0..segments {
                let start = segment * len / segments;
                let end = (segment + 1) * len / segments;
                bufs.append(if cfg.independent_segments {
                    IoBuf::copy_from_slice(&data.as_ref()[start..end])
                } else {
                    data.slice(start..end)
                });
            }
            return (data, bufs);
        }
        let logical = page_size(cfg.physical_page_size).get() as usize;
        let mut data = vec![0u8; logical * cfg.pages];
        rng.fill_bytes(&mut data);
        let mut crcs = Vec::with_capacity(CHECKSUM_SIZE as usize * cfg.pages);
        for page in data.chunks_exact(logical) {
            crcs.extend_from_slice(&(logical as u16).to_be_bytes());
            crcs.extend_from_slice(&Crc32::checksum(page).to_be_bytes());
            crcs.extend_from_slice(&[0u8; 6]);
        }
        let data = IoBuf::from(data);
        let crcs = IoBuf::from(crcs);
        let mut bufs = IoBufs::default();
        for page in 0..cfg.pages {
            bufs.append(data.slice(page * logical..(page + 1) * logical));
            let start = page * CHECKSUM_SIZE as usize;
            bufs.append(crcs.slice(start..start + CHECKSUM_SIZE as usize));
        }
        (data, bufs)
    }

    #[derive(Default)]
    struct Stats {
        ops: u64,
        samples: Vec<u64>,
        verified_pages: usize,
        verified_bytes: usize,
    }

    fn run_loop(
        cfg: &Config,
        backend: &Backend,
        pool: &BufferPool,
        sources: &[IoBufs],
        slots: usize,
        deadline: Instant,
        record: bool,
    ) -> Result<Stats> {
        let mut stats = Stats::default();
        let size = sources[0].len();
        loop {
            if stats.ops.is_multiple_of(8) && Instant::now() >= deadline {
                break;
            }
            // A deterministic hash spreads samples across source positions.
            let sample = stats
                .ops
                .wrapping_add(cfg.seed)
                .wrapping_mul(0x9E3779B97F4A7C15);
            let started = (record && sample >> 60 == 0).then(Instant::now);
            let source = sources[stats.ops as usize % sources.len()].clone();
            let buffers = match cfg.strategy {
                Strategy::Vectored => source,
                Strategy::Coalesce => source.coalesce().into(),
                Strategy::Pool => source.coalesce_with_pool(pool).into(),
            };
            let offset = (stats.ops as usize % slots) * size;
            backend.write(offset as u64, buffers, cfg.durable)?;
            if let Some(started) = started {
                stats.samples.push(started.elapsed().as_nanos() as u64);
            }
            stats.ops += 1;
        }
        Ok(stats)
    }

    struct Worker {
        backend: Backend,
        sources: Vec<IoBufs>,
        pool: BufferPool,
    }

    pub fn main() -> Result<()> {
        let cfg = Config::parse();
        if cfg!(target_os = "macos") && matches!(cfg.layer, Layer::Syscall) {
            return Err(Error::Invalid(
                "the syscall layer is Linux only; use runtime or paged".into(),
            ));
        }
        if cfg.pages == 0 || cfg.writers == 0 || cfg.writers > 64 || cfg.duration_ms == 0 {
            return Err(Error::Invalid(
                "pages, duration and writers must be positive; writers <= 64".into(),
            ));
        }
        if !cfg.physical_page_size.is_power_of_two()
            || cfg.physical_page_size <= CHECKSUM_SIZE as u32
            || cfg.physical_page_size > 65536
        {
            return Err(Error::Invalid(
                "physical page size must be a power of two in 16..=65536".into(),
            ));
        }
        let page_bytes = cfg
            .pages
            .checked_mul(cfg.physical_page_size as usize)
            .ok_or_else(|| Error::Invalid("write size overflow".into()))?;
        let size = cfg.write_bytes.unwrap_or(page_bytes);
        if let Some(segments) = cfg.segments
            && (segments == 0
                || segments > size
                || size > 4 * MIB
                || size.checked_mul(segments).is_none()
                || matches!(cfg.layer, Layer::Paged))
        {
            return Err(Error::Invalid("uniform layout needs 1 <= segments <= bytes <= 4 MiB and the syscall or runtime layer".into()));
        }
        let total = cfg
            .file_mib
            .checked_mul(MIB)
            .filter(|&n| n <= i64::MAX as usize)
            .ok_or_else(|| Error::Invalid("file size overflow".into()))?;
        let slots = (total / cfg.writers) / size;
        if slots == 0 {
            return Err(Error::Invalid(
                "file budget is smaller than one write per writer".into(),
            ));
        }
        if matches!(cfg.layer, Layer::Paged) {
            return paged::run(cfg, slots);
        }
        let source_bytes = cfg
            .source_mib
            .checked_mul(MIB)
            .ok_or_else(|| Error::Invalid("source size overflow".into()))?;
        let source_count = source_bytes.div_ceil(size).max(1);
        let root = cfg.root.join(format!("coalescing-{}", std::process::id()));
        fs::create_dir(&root)?;
        let runtime_cfg = tokio::Config::default()
            .with_worker_threads(4)
            .with_storage_directory(root.clone());
        let cfg = &cfg;
        let work_root = &root;
        let result = tokio::Runner::new(runtime_cfg).start(|context| async move {
            let pool = context.storage_buffer_pool().clone();
            let mut workers = Vec::with_capacity(cfg.writers);
            let mut fill_rng = TestRng::new(cfg.seed);
            let mut fill = vec![0u8; MIB];
            fill_rng.fill_bytes(&mut fill);
            for writer in 0..cfg.writers {
                let bytes = slots * size;
                let backend = match cfg.layer {
                    Layer::Syscall => {
                        let file = OpenOptions::new()
                            .create_new(true)
                            .read(true)
                            .write(true)
                            .open(work_root.join(format!("writer-{writer}")))?;
                        file.set_len(bytes as u64)?;
                        for offset in (0..bytes).step_by(MIB) {
                            let len = (bytes - offset).min(MIB);
                            file.write_all_at(&fill[..len], offset as u64)?;
                        }
                        file.sync_data()?;
                        Backend::Syscall(file)
                    }
                    Layer::Runtime => {
                        let (blob, _) = context.open("coalescing", &writer.to_be_bytes()).await?;
                        for offset in (0..bytes).step_by(MIB) {
                            let len = (bytes - offset).min(MIB);
                            blob.write_at(
                                offset as u64,
                                fill[..len].to_vec(),
                                WriteOptions::default(),
                            )
                            .await?;
                        }
                        blob.sync().await?;
                        Backend::Runtime {
                            blob,
                            handle: ::tokio::runtime::Handle::current(),
                        }
                    }
                    Layer::Paged => unreachable!(),
                };
                let mut rng = TestRng::new(cfg.seed.wrapping_add(writer as u64));
                let sources = (0..source_count).map(|_| payload(cfg, &mut rng)).collect();
                workers.push(Worker {
                    backend,
                    sources,
                    pool: pool.clone(),
                });
            }
            let ready = Arc::new(Barrier::new(cfg.writers + 1));
            let start = Arc::new(Barrier::new(cfg.writers + 1));
            let done = Arc::new(Barrier::new(cfg.writers + 1));
            let release = Arc::new(Barrier::new(cfg.writers + 1));
            let deadline = Arc::new(OnceLock::new());
            let (wall, cpu, results) = thread::scope(|scope| -> Result<_> {
                let mut handles = Vec::new();
                for worker in workers {
                    let (ready, start, done, release, deadline) = (
                        ready.clone(),
                        start.clone(),
                        done.clone(),
                        release.clone(),
                        deadline.clone(),
                    );
                    handles.push(scope.spawn(move || {
                        // Warmup contents cannot satisfy measured write readback.
                        let mut warmup_rng = TestRng::new(cfg.seed ^ 0xA0761D6478BD642F);
                        let warmup_sources = (0..worker.sources.len())
                            .map(|_| payload(cfg, &mut warmup_rng))
                            .collect::<Vec<_>>();
                        let warmup = run_loop(
                            cfg,
                            &worker.backend,
                            &worker.pool,
                            &warmup_sources,
                            slots,
                            Instant::now() + Duration::from_millis(cfg.warmup_ms),
                            false,
                        )
                        .and_then(|_| worker.backend.sync());
                        drop(warmup_sources);
                        ready.wait();
                        start.wait();
                        let result = warmup.and_then(|_| {
                            run_loop(
                                cfg,
                                &worker.backend,
                                &worker.pool,
                                &worker.sources,
                                slots,
                                *deadline.get().unwrap(),
                                true,
                            )
                        });
                        done.wait();
                        release.wait();
                        let mut stats = result?;
                        worker.backend.sync()?;
                        for (slot, op) in crate::checks::final_writes(stats.ops, slots)
                            .map_err(|e| Error::Invalid(e.into()))?
                        {
                            worker.backend.verify(
                                (slot * size) as u64,
                                &worker.sources[op as usize % worker.sources.len()],
                                if cfg.segments.is_some() { 0 } else { cfg.physical_page_size as usize },
                            )?;
                            stats.verified_pages += if cfg.segments.is_some() { 0 } else { cfg.pages };
                            stats.verified_bytes += size;
                        }
                        Ok::<_, Error>(stats)
                    }));
                }
                ready.wait();
                let cpu_start = cpu_time();
                let wall_start = Instant::now();
                deadline
                    .set(wall_start + Duration::from_millis(cfg.duration_ms))
                    .unwrap();
                start.wait();
                done.wait();
                let wall = wall_start.elapsed();
                let cpu_end = cpu_time();
                release.wait();
                let results = handles
                    .into_iter()
                    .map(|h| {
                        h.join()
                            .map_err(|_| Error::Invalid("benchmark worker panicked".into()))?
                    })
                    .collect::<Result<Vec<_>>>()?;
                Ok((wall, cpu_end? - cpu_start?, results))
            })?;
            let ops: u64 = results.iter().map(|s| s.ops).sum();
            for writer in 0..cfg.writers {
                let bytes = match cfg.layer {
                    Layer::Syscall => {
                        fs::metadata(work_root.join(format!("writer-{writer}")))?.len()
                    }
                    Layer::Runtime => context.open("coalescing", &writer.to_be_bytes()).await?.1,
                    Layer::Paged => unreachable!(),
                };
                if bytes != (slots * size) as u64 {
                    return Err(Error::Invalid(
                        "overwrite file has an unexpected physical length".into(),
                    ));
                }
            }
            let verified_pages: usize = results.iter().map(|s| s.verified_pages).sum();
            let verified_bytes: usize = results.iter().map(|s| s.verified_bytes).sum();
            let mut samples: Vec<_> = results.into_iter().flat_map(|s| s.samples).collect();
            samples.sort_unstable();
            let percentile = |p: usize| -> f64 {
                if samples.is_empty() {
                    return 0.0;
                }
                samples[(samples.len() - 1) * p / 100] as f64 / 1000.0
            };
            let result = json!({
                "strategy": format!("{:?}", cfg.strategy).to_lowercase(),
                "platform": std::env::consts::OS, "architecture": std::env::consts::ARCH,
                "layer": format!("{:?}", cfg.layer).to_lowercase(),
                "physical_page_size": cfg.physical_page_size,
                "logical_page_size": page_size(cfg.physical_page_size).get(),
                "crc_record_size": CHECKSUM_SIZE,
                "pages": cfg.segments.is_none().then_some(cfg.pages),
                "fragments": cfg.segments.unwrap_or(cfg.pages * 2),
                "layout": if cfg.segments.is_some() { "uniform" } else { "paged" },
                "independent_segments": cfg.independent_segments,
                "bytes_per_write": size, "writers": cfg.writers,
                "durable": cfg.durable, "file_bytes": slots * size * cfg.writers,
                "source_bytes_per_writer": source_count * size,
                "source_count": source_count,
                "pool_max_size": pool.config().max_size().get(),
                "pool_size_eligible": size <= pool.config().max_size().get(),
                "seed": cfg.seed, "warmup_ms": cfg.warmup_ms,
                "requested_duration_ms": cfg.duration_ms,
                "wall_seconds": wall.as_secs_f64(), "cpu_seconds": cpu.as_secs_f64(),
                "ops": ops, "ops_per_second": ops as f64 / wall.as_secs_f64(),
                "mib_per_second": ops as f64 * size as f64 / MIB as f64 / wall.as_secs_f64(),
                "cpu_ns_per_op": cpu.as_nanos() as f64 / ops as f64,
                "p50_us": percentile(50), "p95_us": percentile(95), "p99_us": percentile(99),
                "latency_samples": samples.len(), "latency_sampling": "deterministic_hash_1_in_16",
                "verified_pages": verified_pages,
                "verified_bytes": verified_bytes,
                "verification": if cfg.segments.is_some() { "all_final_written_slots_bytes_and_exact_length" } else { "all_final_written_slots_bytes_crc_and_exact_length" },
            });
            Ok::<_, Error>(result)
        });
        fs::remove_dir_all(&root)?;
        println!("{}", result?);
        Ok(())
    }

    mod paged {
        use super::*;
        include!("paged_coalescing.rs");
    }
}
