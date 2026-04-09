module tests_n6f1b0_blocks {
    import types.* from "../types"
    import defs.* from "../defs"
    import option.* from "../option"
    import tests_n6f1b0_params.* from "./tests_n6f1b0_params"
    import replica(
        N = PARAM_N,
        F = PARAM_F,
        CORRECT = PARAM_CORRECT,
        REPLICA_KEYS = PARAM_REPLICA_KEYS,
        BYZANTINE = PARAM_BYZANTINE,
        VIEWS = PARAM_VIEWS,
        VALID_BLOCKS = PARAM_VALID_BLOCKS,
        INVALID_BLOCKS = PARAM_INVALID_BLOCKS
    ).* from "../replica"

    run twoBlocksTest = {
        val proposal1 = {
            block: "val_b0",
            view: 0,
            view_parent: GENESIS_VIEW,
            block_parent: GENESIS_BLOCK,
            sig: sig_of("n0")
        }

        val proposal2 = {
            block: "val_b1",
            view: 1,
            view_parent: 0,
            block_parent: "val_b0",
            sig: sig_of("n1")
        }

        initWithLeader(Map(0 -> "n0", 1 -> "n1", 2 -> "n1", 3 -> "n2", 4 -> "n3", 5 -> "n4"))

            // === FIRST BLOCK (VIEW 1) ===
            // Leader n0 proposes in view 1
            .then(proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW))
            .expect(all_invariants)

            // All replicas process the proposal and vote for it (n0 did it already)
            .then(on_proposal("n1", proposal1))
            .then(on_proposal("n2", proposal1))
            .then(on_proposal("n3", proposal1))
            .then(on_proposal("n4", proposal1))
            .then(on_proposal("n5", proposal1))
            .expect(all_invariants)

            // All replicas collect votes for block 1
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n5"))

            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n5"))

            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n5"))

            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n5"))

            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n5"))

            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n5"))

            // Verify first block is finalized and committed
            .expect(is_view_finalized_votes(0, store_vote.get("n0"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n1"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n2"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n3"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n4"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n5"), "val_b0"))

            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n1")))
            .expect(is_view_notarized(0, store_certificate.get("n2")))
            .expect(is_view_notarized(0, store_certificate.get("n3")))
            .expect(is_view_notarized(0, store_certificate.get("n4")))
            .expect(is_view_notarized(0, store_certificate.get("n5")))

            // Check first block is committed and replicas advance to view 1
            .then(all {
                assert(replica_state.get("n0").last_finalized == 0),
                assert(replica_state.get("n1").last_finalized == 0),
                assert(replica_state.get("n2").last_finalized == 0),
                assert(replica_state.get("n3").last_finalized == 0),
                assert(replica_state.get("n4").last_finalized == 0),
                assert(replica_state.get("n5").last_finalized == 0),

                assert(replica_state.get("n0").view == 1),
                assert(replica_state.get("n1").view == 1),
                assert(replica_state.get("n2").view == 1),
                assert(replica_state.get("n3").view == 1),
                assert(replica_state.get("n4").view == 1),
                assert(replica_state.get("n5").view == 1),

                assert(ghost_committed_blocks.get("n0") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n1") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n2") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n3") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n4") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n5") == ["val_b0"]),

                unchanged_all,
            })

            // === SECOND BLOCK (VIEW 1) ===
            // Leader n1 proposes in view 1
            .then(proposer_step("n1", "val_b1", "val_b0", 0))
            .expect(all_invariants)

            // All replicas process the second proposal and vote for it (n1 already did!)
            .then(on_proposal("n0", proposal2))
            //.then(on_proposal("n1", proposal2))
            .then(on_proposal("n2", proposal2))
            .then(on_proposal("n3", proposal2))
            .then(on_proposal("n4", proposal2))
            .then(on_proposal("n5", proposal2))
            .expect(all_invariants)

            // All replicas collect votes for block 2
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n5"))

            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n5"))

            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n5"))

            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n5"))

            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n5"))

            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n5"))

            // Verify second block is finalized and committed
            .expect(is_view_finalized_votes(1, store_vote.get("n0"), "val_b1"))
            .expect(is_view_finalized_votes(1, store_vote.get("n1"), "val_b1"))
            .expect(is_view_finalized_votes(1, store_vote.get("n2"), "val_b1"))
            .expect(is_view_finalized_votes(1, store_vote.get("n3"), "val_b1"))
            .expect(is_view_finalized_votes(1, store_vote.get("n4"), "val_b1"))
            .expect(is_view_finalized_votes(1, store_vote.get("n5"), "val_b1"))

            .expect(is_view_notarized(1, store_certificate.get("n0")))
            .expect(is_view_notarized(1, store_certificate.get("n1")))
            .expect(is_view_notarized(1, store_certificate.get("n2")))
            .expect(is_view_notarized(1, store_certificate.get("n3")))
            .expect(is_view_notarized(1, store_certificate.get("n4")))
            .expect(is_view_notarized(1, store_certificate.get("n5")))

            // Check both blocks are committed and replicas advance to view 3
            .then(all {
                assert(replica_state.get("n0").last_finalized == 1),
                assert(replica_state.get("n1").last_finalized == 1),
                assert(replica_state.get("n2").last_finalized == 1),
                assert(replica_state.get("n3").last_finalized == 1),
                assert(replica_state.get("n4").last_finalized == 1),
                assert(replica_state.get("n5").last_finalized == 1),

                assert(replica_state.get("n0").view == 2),
                assert(replica_state.get("n1").view == 2),
                assert(replica_state.get("n2").view == 2),
                assert(replica_state.get("n3").view == 2),
                assert(replica_state.get("n4").view == 2),
                assert(replica_state.get("n5").view == 2),

                // Both blocks should be in the committed chain
                assert(ghost_committed_blocks.get("n0") == ["val_b0", "val_b1"]),
                assert(ghost_committed_blocks.get("n1") == ["val_b0", "val_b1"]),
                assert(ghost_committed_blocks.get("n2") == ["val_b0", "val_b1"]),
                assert(ghost_committed_blocks.get("n3") == ["val_b0", "val_b1"]),
                assert(ghost_committed_blocks.get("n4") == ["val_b0", "val_b1"]),
                assert(ghost_committed_blocks.get("n5") == ["val_b0", "val_b1"]),

                unchanged_all,
            })
            .expect(all_invariants)

            // replicas can receive old votes
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n5"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n0"))
    }

    // Two blocks happy path test - but notarization and finalizations are processed in different views
    run twoBlocksDifferentViewsTest = {
        val proposal1 = {
            block: "val_b0",
            view: 0,
            view_parent: GENESIS_VIEW,
            block_parent: GENESIS_BLOCK,
            sig: sig_of("n0")
        }

        val proposal2 = {
            block: "val_b1",
            view: 1,
            view_parent: 0,
            block_parent: "val_b0",
            sig: sig_of("n1")
        }

        initWithLeader(Map(0 -> "n0", 1 -> "n1", 2 -> "n1", 3 -> "n2", 4 -> "n3", 5 -> "n4"))

            // === FIRST BLOCK (VIEW 1) ===
            // Leader n0 proposes in view 1
            .then(proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW))
            .expect(all_invariants)

            // All replicas process the proposal and vote for it (n0 did it already)
            .then(on_proposal("n1", proposal1))
            .then(on_proposal("n2", proposal1))
            .then(on_proposal("n3", proposal1))
            .then(on_proposal("n4", proposal1))
            .then(on_proposal("n5", proposal1))
            .expect(all_invariants)

            // All replicas collect semiquorum for block 1
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n2"))

            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n5"))

            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n3"))

            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n4"))

            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n5"))

            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n5"))

            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n0")))

            .expect(not(is_view_finalized_votes(0, store_vote.get("n0"), "val_b0")))
            .expect(not(is_view_finalized_votes(0, store_vote.get("n1"), "val_b0")))
            .expect(not(is_view_finalized_votes(0, store_vote.get("n2"), "val_b0")))
            .expect(not(is_view_finalized_votes(0, store_vote.get("n3"), "val_b0")))
            .expect(not(is_view_finalized_votes(0, store_vote.get("n4"), "val_b0")))
            .expect(not(is_view_finalized_votes(0, store_vote.get("n5"), "val_b0")))

            .then(all {
                assert(replica_state.get("n0").last_finalized == GENESIS_VIEW),
                assert(replica_state.get("n1").last_finalized == GENESIS_VIEW),
                assert(replica_state.get("n2").last_finalized == GENESIS_VIEW),
                assert(replica_state.get("n3").last_finalized == GENESIS_VIEW),
                assert(replica_state.get("n4").last_finalized == GENESIS_VIEW),
                assert(replica_state.get("n5").last_finalized == GENESIS_VIEW),

                assert(replica_state.get("n0").view == 1),
                assert(replica_state.get("n1").view == 1),
                assert(replica_state.get("n2").view == 1),
                assert(replica_state.get("n3").view == 1),
                assert(replica_state.get("n4").view == 1),
                assert(replica_state.get("n5").view == 1),

                assert(ghost_committed_blocks.get("n0") == []),
                assert(ghost_committed_blocks.get("n1") == []),
                assert(ghost_committed_blocks.get("n2") == []),
                assert(ghost_committed_blocks.get("n3") == []),
                assert(ghost_committed_blocks.get("n4") == []),
                assert(ghost_committed_blocks.get("n5") == []),

                unchanged_all,
            })

            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n5"))

            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n2"))

            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n5"))

            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n5"))

            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n2"))

            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n3"))

            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n0")))

            // Verify first block is finalized and committed
            .expect(is_view_finalized_votes(0, store_vote.get("n0"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n1"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n2"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n3"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n4"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n5"), "val_b0"))

            // Check first block is committed and replicas advance to view 2
            .then(all {
                assert(replica_state.get("n0").last_finalized == 0),
                assert(replica_state.get("n1").last_finalized == 0),
                assert(replica_state.get("n2").last_finalized == 0),
                assert(replica_state.get("n3").last_finalized == 0),
                assert(replica_state.get("n4").last_finalized == 0),
                assert(replica_state.get("n5").last_finalized == 0),

                assert(replica_state.get("n0").view == 1),
                assert(replica_state.get("n1").view == 1),
                assert(replica_state.get("n2").view == 1),
                assert(replica_state.get("n3").view == 1),
                assert(replica_state.get("n4").view == 1),
                assert(replica_state.get("n5").view == 1),

                assert(ghost_committed_blocks.get("n0") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n1") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n2") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n3") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n4") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n5") == ["val_b0"]),

                unchanged_all,
            })

            // === SECOND BLOCK (VIEW 1) ===
            // Leader n1 proposes in view 1
            .then(proposer_step("n1", "val_b1", "val_b0", 0))
            .expect(all_invariants)

            // All replicas process the second proposal and vote for it (n1 already did!)
            .then(on_proposal("n0", proposal2))
            .then(on_proposal("n2", proposal2))
            .then(on_proposal("n3", proposal2))
            .then(on_proposal("n4", proposal2))
            .then(on_proposal("n5", proposal2))
            .expect(all_invariants)

            // All replicas collect votes for block 2
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n0", "val_b1", 1, "n5"))

            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n1", "val_b1", 1, "n5"))

            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n2", "val_b1", 1, "n5"))

            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n3", "val_b1", 1, "n5"))

            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n4", "val_b1", 1, "n5"))

            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n0"))
            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n1"))
            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n2"))
            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n3"))
            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n4"))
            .then(replica_receives_notarize_vote("n5", "val_b1", 1, "n5"))

            // Verify second block is finalized and committed
            .expect(is_view_finalized_votes(1, store_vote.get("n0"), "val_b1"))
            .expect(is_view_finalized_votes(1, store_vote.get("n1"), "val_b1"))
            .expect(is_view_finalized_votes(1, store_vote.get("n2"), "val_b1"))
            .expect(is_view_finalized_votes(1, store_vote.get("n3"), "val_b1"))
            .expect(is_view_finalized_votes(1, store_vote.get("n4"), "val_b1"))
            .expect(is_view_finalized_votes(1, store_vote.get("n5"), "val_b1"))

            .expect(is_view_notarized(1, store_certificate.get("n0")))
            .expect(is_view_notarized(1, store_certificate.get("n1")))
            .expect(is_view_notarized(1, store_certificate.get("n2")))
            .expect(is_view_notarized(1, store_certificate.get("n3")))
            .expect(is_view_notarized(1, store_certificate.get("n4")))
            .expect(is_view_notarized(1, store_certificate.get("n5")))


            // Check both blocks are committed and replicas advance to view 3
            .then(all {
                assert(replica_state.get("n0").last_finalized == 1),
                assert(replica_state.get("n1").last_finalized == 1),
                assert(replica_state.get("n2").last_finalized == 1),
                assert(replica_state.get("n3").last_finalized == 1),
                assert(replica_state.get("n4").last_finalized == 1),
                assert(replica_state.get("n5").last_finalized == 1),

                assert(replica_state.get("n0").view == 2),
                assert(replica_state.get("n1").view == 2),
                assert(replica_state.get("n2").view == 2),
                assert(replica_state.get("n3").view == 2),
                assert(replica_state.get("n4").view == 2),
                assert(replica_state.get("n5").view == 2),

                // Both blocks should be in the committed chain
                assert(ghost_committed_blocks.get("n0") == ["val_b0", "val_b1"]),
                assert(ghost_committed_blocks.get("n1") == ["val_b0", "val_b1"]),
                assert(ghost_committed_blocks.get("n2") == ["val_b0", "val_b1"]),
                assert(ghost_committed_blocks.get("n3") == ["val_b0", "val_b1"]),
                assert(ghost_committed_blocks.get("n4") == ["val_b0", "val_b1"]),
                assert(ghost_committed_blocks.get("n5") == ["val_b0", "val_b1"]),

                unchanged_all,
            })

            .expect(all_invariants)
    }



    action replica_receives_notarize_vote(id: ReplicaId, block: Block, view: ViewNumber, src: ReplicaId): bool =
        on_vote_notarize(id, view, block,  Set(notarize(view, src, block)))
    
    action replica_receives_certificate(id: ReplicaId, cert: Certificate): bool =
        on_certificate(id, cert)

    action replica_receives_nullify_vote(id: ReplicaId, view: ViewNumber, src: str): bool =
        on_vote_nullify(id, view, Set(nullify(view, src)))

    action unchanged_all = all {
        sent_proposal' = sent_proposal,
        sent_vote' = sent_vote,
        sent_certificate' = sent_certificate,
        store_vote' = store_vote,
        store_certificate' = store_certificate,
        ghost_proposal' = ghost_proposal,
        ghost_committed_blocks' = ghost_committed_blocks,
        leader' = leader,
        replica_state' = replica_state,
    }
}
