//! Expected final contents of a cyclic overwrite workload.

pub fn final_writes(ops: u64, slots: usize) -> Result<Vec<(usize, u64)>, &'static str> {
    if ops == 0 || slots == 0 {
        return Err("a trial must complete work in at least one slot");
    }
    let count = ops.min(slots as u64);
    Ok((ops - count..ops)
        .map(|op| ((op % slots as u64) as usize, op))
        .collect())
}

#[cfg(test)]
mod tests {
    #[test]
    fn detects_an_interior_write_that_never_happened() {
        let actual = [Some(0), None, Some(2)];
        let checks = super::final_writes(3, 3).unwrap();
        assert!(checks.iter().any(|&(slot, op)| actual[slot] != Some(op)));
    }

    #[test]
    fn rejects_trials_without_completed_work() {
        assert!(super::final_writes(0, 3).is_err());
    }

    #[test]
    fn agrees_with_sequential_overwrites_including_wraparound() {
        for slots in 1..20 {
            for ops in 1..100 {
                let mut expected = vec![None; slots];
                for op in 0..ops {
                    expected[op as usize % slots] = Some(op);
                }
                let mut checked = vec![None; slots];
                for (slot, op) in super::final_writes(ops, slots).unwrap() {
                    assert!(checked[slot].replace(op).is_none());
                }
                assert_eq!(checked, expected);
            }
        }
    }
}
