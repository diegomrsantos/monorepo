module tests_n6f1b0_basic {
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

    run asuumptionsValidTest = all {
        L == 5,
        M == 3,
        assumptions_valid
    }

    // Simple init test
    run initTest = {
        initWithLeader(Map(0 -> "n0", 1 -> "n0", 2 -> "n1", 3 -> "n2", 4 -> "n3", 5 -> "n4"))
            .then(all {
                assert(replica_state.get("n0").view == 0),
                assert(replica_state.get("n1").view == 0),
                assert(replica_state.get("n2").view == 0),
                assert(replica_state.get("n3").view == 0),
                assert(replica_state.get("n4").view == 0),
                assert(replica_state.get("n5").view == 0),
                assert(leader.get(1) == "n0"),
                unchanged_all
            })}

    // Minimal test without init
    run minimalProposalTest = {
        // Manual state setup
        initWithLeader(Map(0 -> "n0", 1 -> "n0", 2 -> "n1", 3 -> "n2", 4 -> "n3", 5 -> "n4"))
        .then(proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW))
        .then(all {
            assert(sent_proposal.size() == 1),
            unchanged_all
        })
    }

    run happyPathTest = {
        val proposal = {
            block: "val_b0",
            view: 0,
            view_parent: GENESIS_VIEW,
            block_parent: GENESIS_BLOCK,
            sig: sig_of("n0")
        }

        initWithLeader(Map(0 -> "n0", 1 -> "n0", 2 -> "n1", 3 -> "n2", 4 -> "n3", 5 -> "n4"))
            // Leader n0 proposes in view 0
            .then(proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW))
            .then( all {
                assert(replica_state.get("n0").notarized.get(0)=="val_b0"),
                unchanged_all
            })
            .expect(all_invariants)
            // All replicas process the proposal and vote for it (n0 already did!)
            .then(on_proposal("n1", proposal))
            .then( all {
                assert(replica_state.get("n1").notarized.get(0)=="val_b0"),
                unchanged_all
            })
            .then(on_proposal("n2", proposal))
            .then( all {
                assert(replica_state.get("n2").notarized.get(0)=="val_b0"),
                unchanged_all
            })
            .then(on_proposal("n3", proposal))
            .then( all {
                assert(replica_state.get("n3").notarized.get(0)=="val_b0"),
                unchanged_all
            })
            .then(on_proposal("n4", proposal))
            .then( all {
                assert(replica_state.get("n4").notarized.get(0)=="val_b0"),
                unchanged_all
            })
            .then(on_proposal("n5", proposal))
            .then( all {
                assert(replica_state.get("n5").notarized.get(0)=="val_b0"),
                unchanged_all
            })
            .expect(all_invariants)

            // All replicas collect votes and notarize the block
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n1"))
            .then(all{
                assert(store_certificate.get("n0").size() == 0),
                assert(replica_state.get("n0").ghost_last_seen_notarization==-1),
                assert(replica_state.get("n0").view==0),
                assert(replica_state.get("n0").last_finalized==-1),
                unchanged_all
            })
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n2"))
            .then(all{
                assert(replica_state.get("n0").view==1),
                assert(replica_state.get("n0").ghost_last_seen_notarization==0),
                assert(replica_state.get("n0").last_finalized==-1),
                assert(store_certificate.get("n0").size() == 1),
                assert(store_certificate.get("n1").size() == 0),
                assert(is_view_notarized(0, store_certificate.get("n0"))),
                assert(is_view_notarized_votes(0, store_vote.get("n0"), proposal.block)),
                unchanged_all
            })
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n3"))
            .then(all{
                assert(store_certificate.get("n0").size() == 1),
                unchanged_all
            })
            
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n4"))
            .then(all{
                assert(store_certificate.get("n0").size() == 2),
                assert(replica_state.get("n0").ghost_last_seen_notarization==0),
                assert(replica_state.get("n0").last_finalized==0),
                unchanged_all
            })

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

            .expect(select_votes(0, NotarizeKind, store_vote.get("n0")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n1")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n2")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n3")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n4")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n5")).size()==6)

            .expect(is_view_finalized_votes(0, store_vote.get("n0"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n0"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n1"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n2"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n3"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n4"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n5"), "val_b0"))

            .expect(store_certificate.get("n0").size() == 2)
            .expect(store_certificate.get("n1").size() == 2)
            .expect(store_certificate.get("n2").size() == 2)
            .expect(store_certificate.get("n3").size() == 2)
            .expect(store_certificate.get("n4").size() == 2)
            .expect(store_certificate.get("n5").size() == 2)

            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n1")))
            .expect(is_view_notarized(0, store_certificate.get("n2")))
            .expect(is_view_notarized(0, store_certificate.get("n3")))
            .expect(is_view_notarized(0, store_certificate.get("n4")))
            .expect(is_view_notarized(0, store_certificate.get("n5")))
            .expect(all_invariants)

            .then(all {
                assert(replica_state.get("n0").last_finalized == 0),
                assert(replica_state.get("n1").last_finalized == 0),
                assert(replica_state.get("n2").last_finalized == 0),
                assert(replica_state.get("n3").last_finalized == 0),
                assert(replica_state.get("n4").last_finalized == 0),
                assert(replica_state.get("n5").last_finalized == 0),
                unchanged_all,
            })

            .then(all {
                assert(replica_state.get("n0").view == 1),
                assert(replica_state.get("n1").view == 1),
                assert(replica_state.get("n2").view == 1),
                assert(replica_state.get("n3").view == 1),
                assert(replica_state.get("n4").view == 1),
                assert(replica_state.get("n5").view == 1),
                unchanged_all,
            })

            .then(all {
                assert(ghost_committed_blocks.get("n0") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n1") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n2") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n3") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n4") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n5") == ["val_b0"]),
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
