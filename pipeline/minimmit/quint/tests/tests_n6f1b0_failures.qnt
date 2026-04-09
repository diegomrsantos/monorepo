module tests_n6f1b0_failures {
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

    run timeoutTest = {
        // ----- first block (view 1) -----
        val proposal1 = {
            block: "val_b0",
            block_parent: GENESIS_BLOCK,
            view: 0,
            view_parent: GENESIS_VIEW,
            sig: sig_of("n0")
        }

        initWithLeader(Map(0 -> "n0", 1 -> "n5", 2 -> "n1", 3 -> "n2", 4 -> "n3", 5 -> "n4"))
            // === view 0 ===
            .then(proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW)) // leader n0 proposes, view 0
            .expect(all_invariants)
            // n0 has sent notarize vote for its proposal in proposer_step, but all other replicas do not see it
            .then(on_timer_expired("n1"))
            .then(on_timer_expired("n2"))
            .then(on_timer_expired("n3"))
            .then(on_timer_expired("n4"))
            .then(on_timer_expired("n5"))
            .expect(all_invariants)

            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n0"))

            .then(replica_receives_nullify_vote("n1", 0, "n1"))
            .then(replica_receives_nullify_vote("n1", 0, "n2"))
            .then(replica_receives_nullify_vote("n1", 0, "n3"))
            .then(replica_receives_nullify_vote("n1", 0, "n4"))
            .then(replica_receives_nullify_vote("n1", 0, "n5"))

            .then(replica_receives_nullify_vote("n2", 0, "n1"))
            .then(replica_receives_nullify_vote("n2", 0, "n2"))
            .then(replica_receives_nullify_vote("n2", 0, "n3"))
            .then(replica_receives_nullify_vote("n2", 0, "n4"))
            .then(replica_receives_nullify_vote("n2", 0, "n5"))

            .then(replica_receives_nullify_vote("n3", 0, "n1"))
            .then(replica_receives_nullify_vote("n3", 0, "n2"))
            .then(replica_receives_nullify_vote("n3", 0, "n3"))
            .then(replica_receives_nullify_vote("n3", 0, "n4"))
            .then(replica_receives_nullify_vote("n3", 0, "n5"))

            .then(replica_receives_nullify_vote("n4", 0, "n1"))
            .then(replica_receives_nullify_vote("n4", 0, "n2"))
            .then(replica_receives_nullify_vote("n4", 0, "n3"))
            .then(replica_receives_nullify_vote("n4", 0, "n4"))
            .then(replica_receives_nullify_vote("n4", 0, "n5"))

            .then(replica_receives_nullify_vote("n5", 0, "n1"))
            .then(replica_receives_nullify_vote("n5", 0, "n2"))
            .then(replica_receives_nullify_vote("n5", 0, "n3"))
            .then(replica_receives_nullify_vote("n5", 0, "n4"))
            .then(replica_receives_nullify_vote("n5", 0, "n5"))

            .then(all {
                assert(replica_state.get("n0").view == 0),
                assert(replica_state.get("n1").view == 1),
                assert(replica_state.get("n2").view == 1),
                assert(replica_state.get("n3").view == 1),
                assert(replica_state.get("n4").view == 1),
                assert(replica_state.get("n5").view == 1),
                unchanged_all,
            })
            .expect(all_invariants)
            .then(all {
                assert(ghost_committed_blocks.get("n0") == []),
                assert(ghost_committed_blocks.get("n1") == []),
                assert(ghost_committed_blocks.get("n2") == []),
                assert(ghost_committed_blocks.get("n3") == []),
                assert(ghost_committed_blocks.get("n4") == []),
                assert(ghost_committed_blocks.get("n5") == []),
                unchanged_all,
            })
    }

    run nullificationTest = {
        // ----- first block (view 1) -----
        val proposal1 = {
            block: "val_b0",
            block_parent: GENESIS_BLOCK,
            view: 0,
            view_parent: GENESIS_VIEW,
            sig: sig_of("n0")
        }

        val nullification_n1n2n3 = {
            view: 0,
            kind: NullificationKind,
            block: DUMMY_BLOCK,
            signatures: Set("n1", "n2", "n3"),
            ghost_sender: sig_of("n1"),
        }

        val nullification_n2n3n4 = {
            view: 0,
            kind: NullificationKind,
            block: DUMMY_BLOCK,
            signatures: Set("n4", "n2", "n3"),
            ghost_sender: sig_of("n2"),
        }

        initWithLeader(Map(0 -> "n0", 1 -> "n5", 2 -> "n1", 3 -> "n2", 4 -> "n3", 5 -> "n4"))
            // === view 0 ===
            .then(proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW)) // leader n0 proposes, view 0
            .expect(all_invariants)
            // n0 has sent notarize vote for its proposal in proposer_step, but all other replicas do not see it
            .then(on_timer_expired("n1"))
            .then(on_timer_expired("n2"))
            .then(on_timer_expired("n3"))
            .then(on_timer_expired("n4"))
            .then(on_timer_expired("n5"))
            .expect(all_invariants)

            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n0"))

            .then(replica_receives_nullify_vote("n1", 0, "n1"))
            .then(replica_receives_nullify_vote("n1", 0, "n2"))
            .then(replica_receives_nullify_vote("n1", 0, "n3"))
            .then(replica_receives_nullify_vote("n1", 0, "n4"))
            

            .then(replica_receives_nullify_vote("n2", 0, "n1"))
            .then(replica_receives_nullify_vote("n2", 0, "n2"))
            .then(replica_receives_nullify_vote("n2", 0, "n3"))
            .then(replica_receives_nullify_vote("n2", 0, "n4"))
            

            .then(replica_receives_nullify_vote("n3", 0, "n1"))
            .then(replica_receives_nullify_vote("n3", 0, "n2"))
            .then(replica_receives_nullify_vote("n3", 0, "n3"))
            .then(replica_receives_nullify_vote("n3", 0, "n4"))

            .then(replica_receives_nullify_vote("n4", 0, "n1"))
            .then(replica_receives_nullify_vote("n4", 0, "n2"))
            .then(replica_receives_nullify_vote("n4", 0, "n3"))
            .then(replica_receives_nullify_vote("n4", 0, "n4"))
        
            .then(replica_receives_certificate("n5", nullification_n1n2n3))

            .then(all{
                assert(store_certificate.get("n5").size() == 1),
                unchanged_all
            })
            .then(all{
                assert(store_certificate.get("n5").size() == 1),
                unchanged_all
            }) 
            .then(all {
                assert(replica_state.get("n0").view == 0),
                assert(replica_state.get("n1").view == 1),
                assert(replica_state.get("n2").view == 1),
                assert(replica_state.get("n3").view == 1),
                assert(replica_state.get("n4").view == 1),
                assert(replica_state.get("n5").view == 1),
                unchanged_all,
            })
            .expect(all_invariants)
            .then(all {
                assert(ghost_committed_blocks.get("n0") == []),
                assert(ghost_committed_blocks.get("n1") == []),
                assert(ghost_committed_blocks.get("n2") == []),
                assert(ghost_committed_blocks.get("n3") == []),
                assert(ghost_committed_blocks.get("n4") == []),
                assert(ghost_committed_blocks.get("n5") == []),
                unchanged_all,
            })
    }

    run contradictionTest = {
        pure val proposal0 = {
            block: "val_b0",
            view: 0,
            view_parent: GENESIS_VIEW,
            block_parent: GENESIS_BLOCK,
            sig: sig_of("n0")
        }

        initWithLeader(Map(0 -> "n0", 1 -> "n5", 2 -> "n1", 3 -> "n2", 4 -> "n3", 5 -> "n1"))
            // === view 0 ===
            .then(proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW))
            .then(on_proposal("n1", proposal0))
            .then(on_proposal("n2", proposal0))

            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n1"))

            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n0"))

            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n1"))

            .then(on_timer_expired("n3"))
            .then(on_timer_expired("n4"))
            .then(on_timer_expired("n5"))

            .then(all {
                assert(replica_state.get("n0").view == 0),
                assert(replica_state.get("n1").view == 0),
                assert(replica_state.get("n2").view == 0),
                assert(replica_state.get("n3").view == 0),
                assert(replica_state.get("n4").view == 0),
                assert(replica_state.get("n5").view == 0),
                unchanged_all,
            })

            .expect(all_invariants)

            .then(replica_receives_nullify_vote("n0", 0, "n3"))
            .then(replica_receives_nullify_vote("n0", 0, "n4"))

            .then(all {
                assert(store_vote.get("n0").filter(v=>v.view==0 and v.kind==NotarizeKind and v.block != "val_b0").size() == 0),
                assert(store_vote.get("n0").filter(v=>v.view==0 and v.kind==NullifyKind).size() == 2),
                assert(replica_state.get("n0").nullified == false),
                assert(replica_state.get("n0").notarized.get(0) == "val_b0"),
                assert(is_contradicted(replica_state.get("n0"), 0, store_vote.get("n0")) == false),
                unchanged_all,
            })

            // no contradiction, no nullification will be sent.

            .then(all {
                assert(store_vote.get("n0").filter(v=>v.view==0).size() == 4),
                assert(replica_state.get("n0").nullified == false),
                unchanged_all,
            })

            // n1 gets vote for block from n0 and 3 nullify votes from n3-n5
            .then(replica_receives_nullify_vote("n1", 0, "n3"))
            .then(all {
                assert(store_vote.get("n1").filter(v=>v.view==0).size() == 2),
                assert(replica_state.get("n1").nullified == false),
                unchanged_all,
            })
            .then(replica_receives_nullify_vote("n1", 0, "n4"))
            .then(replica_receives_nullify_vote("n1", 0, "n5"))
            .then(all {
                assert(store_vote.get("n1").filter(v=>v.view==0 and v.kind==NullifyKind).size() == 3),
                assert(store_vote.get("n1").filter(v=>v.view==0).size() == 4),
                assert(replica_state.get("n1").view == 1),
                unchanged_all,
            })
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
