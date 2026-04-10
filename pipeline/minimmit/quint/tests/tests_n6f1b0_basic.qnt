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

    pure val DEFAULT_LEADERS = Map(0 -> "n0", 1 -> "n0", 2 -> "n1", 3 -> "n2", 4 -> "n3", 5 -> "n4")

    type ActionTaken =
        | InitWithLeader
        | ProposerStep({
            id: ReplicaId,
            block: Block,
            parent_block: Block,
            parent_view: ViewNumber,
        })
        | OnProposal({
            id: ReplicaId,
            block: Block,
            view: ViewNumber,
            parent_block: Block,
            parent_view: ViewNumber,
            sig_source: str,
        })
        | ReplicaReceivesNotarizeVote({
            id: ReplicaId,
            block: Block,
            view: ViewNumber,
            src: ReplicaId,
        })
        | Observe({ label: str })

    var actionTaken: ActionTaken

    action qc_init_with_leader = all {
        initWithLeader(DEFAULT_LEADERS),
        actionTaken' = InitWithLeader,
    }

    action qc_proposer_step(id: ReplicaId, block: Block, parent_block: Block, parent_view: ViewNumber): bool =
        all {
            proposer_step(id, block, parent_block, parent_view),
            actionTaken' = ProposerStep({
                id: id,
                block: block,
                parent_block: parent_block,
                parent_view: parent_view,
            }),
        }

    action qc_on_proposal(id: ReplicaId, proposal: Proposal, sig_source: str): bool =
        all {
            on_proposal(id, proposal),
            actionTaken' = OnProposal({
                id: id,
                block: proposal.block,
                view: proposal.view,
                parent_block: proposal.block_parent,
                parent_view: proposal.view_parent,
                sig_source: sig_source,
            }),
        }

    action replica_receives_notarize_vote(id: ReplicaId, block: Block, view: ViewNumber, src: ReplicaId): bool =
        all {
            on_vote_notarize(id, view, block, Set(notarize(view, src, block))),
            actionTaken' = ReplicaReceivesNotarizeVote({
                id: id,
                block: block,
                view: view,
                src: src,
            }),
        }

    run asuumptionsValidTest = all {
        L == 5,
        M == 3,
        assumptions_valid
    }

    run initTest = {
        qc_init_with_leader
            .then(all {
                assert(replica_state.get("n0").view == 0),
                assert(replica_state.get("n1").view == 0),
                assert(replica_state.get("n2").view == 0),
                assert(replica_state.get("n3").view == 0),
                assert(replica_state.get("n4").view == 0),
                assert(replica_state.get("n5").view == 0),
                assert(leader.get(1) == "n0"),
                actionTaken' = Observe({ label: "init_observe" }),
                unchanged_all
            })
    }

    run minimalProposalTest = {
        qc_init_with_leader
            .then(qc_proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW))
            .then(all {
                assert(sent_proposal.size() == 1),
                actionTaken' = Observe({ label: "minimal_proposal_observe" }),
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

        qc_init_with_leader
            .then(qc_proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW))
            .then(all {
                assert(replica_state.get("n0").notarized.get(0) == "val_b0"),
                actionTaken' = Observe({ label: "happy_after_proposer_step" }),
                unchanged_all
            })
            .expect(all_invariants)
            .then(qc_on_proposal("n1", proposal, "n0"))
            .then(all {
                assert(replica_state.get("n1").notarized.get(0) == "val_b0"),
                actionTaken' = Observe({ label: "happy_after_n1_proposal" }),
                unchanged_all
            })
            .then(qc_on_proposal("n2", proposal, "n0"))
            .then(all {
                assert(replica_state.get("n2").notarized.get(0) == "val_b0"),
                actionTaken' = Observe({ label: "happy_after_n2_proposal" }),
                unchanged_all
            })
            .then(qc_on_proposal("n3", proposal, "n0"))
            .then(all {
                assert(replica_state.get("n3").notarized.get(0) == "val_b0"),
                actionTaken' = Observe({ label: "happy_after_n3_proposal" }),
                unchanged_all
            })
            .then(qc_on_proposal("n4", proposal, "n0"))
            .then(all {
                assert(replica_state.get("n4").notarized.get(0) == "val_b0"),
                actionTaken' = Observe({ label: "happy_after_n4_proposal" }),
                unchanged_all
            })
            .then(qc_on_proposal("n5", proposal, "n0"))
            .then(all {
                assert(replica_state.get("n5").notarized.get(0) == "val_b0"),
                actionTaken' = Observe({ label: "happy_after_n5_proposal" }),
                unchanged_all
            })
            .expect(all_invariants)

            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n1"))
            .then(all {
                assert(store_certificate.get("n0").size() == 0),
                assert(replica_state.get("n0").ghost_last_seen_notarization == -1),
                assert(replica_state.get("n0").view == 0),
                assert(replica_state.get("n0").last_finalized == -1),
                actionTaken' = Observe({ label: "happy_n0_after_two_votes" }),
                unchanged_all
            })
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n2"))
            .then(all {
                assert(replica_state.get("n0").view == 1),
                assert(replica_state.get("n0").ghost_last_seen_notarization == 0),
                assert(replica_state.get("n0").last_finalized == -1),
                assert(store_certificate.get("n0").size() == 1),
                assert(store_certificate.get("n1").size() == 0),
                assert(is_view_notarized(0, store_certificate.get("n0"))),
                assert(is_view_notarized_votes(0, store_vote.get("n0"), proposal.block)),
                actionTaken' = Observe({ label: "happy_n0_after_m_quorum" }),
                unchanged_all
            })
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n3"))
            .then(all {
                assert(store_certificate.get("n0").size() == 1),
                actionTaken' = Observe({ label: "happy_n0_after_n3_vote" }),
                unchanged_all
            })
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n4"))
            .then(all {
                assert(store_certificate.get("n0").size() == 2),
                assert(replica_state.get("n0").ghost_last_seen_notarization == 0),
                assert(replica_state.get("n0").last_finalized == 0),
                actionTaken' = Observe({ label: "happy_n0_after_l_quorum" }),
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

            .expect(select_votes(0, NotarizeKind, store_vote.get("n0")).size() == 6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n1")).size() == 6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n2")).size() == 6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n3")).size() == 6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n4")).size() == 6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n5")).size() == 6)

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
                actionTaken' = Observe({ label: "happy_finalized_block_0" }),
                unchanged_all,
            })

            .then(all {
                assert(replica_state.get("n0").view == 1),
                assert(replica_state.get("n1").view == 1),
                assert(replica_state.get("n2").view == 1),
                assert(replica_state.get("n3").view == 1),
                assert(replica_state.get("n4").view == 1),
                assert(replica_state.get("n5").view == 1),
                actionTaken' = Observe({ label: "happy_entered_view_1" }),
                unchanged_all,
            })

            .then(all {
                assert(ghost_committed_blocks.get("n0") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n1") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n2") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n3") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n4") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n5") == ["val_b0"]),
                actionTaken' = Observe({ label: "happy_committed_block_0" }),
                unchanged_all,
            })
    }

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
