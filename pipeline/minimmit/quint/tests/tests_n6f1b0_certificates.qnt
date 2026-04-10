module tests_n6f1b0_certificates {
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
        | ReplicaReceivesCertificate({
            id: ReplicaId,
            kind: Kind,
            block: Block,
            view: ViewNumber,
            signatures: Set[Signature],
            ghost_sender: Signature,
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

    run n5NodeIsSlowAndGetFinalizationFirstTest = {
        val proposal = {
            block: "val_b0",
            view: 0,
            view_parent: GENESIS_VIEW,
            block_parent: GENESIS_BLOCK,
            sig: sig_of("n0")
        }

        val cert_n0n1n2n3n4 = {
                view: 0,
                kind: FinalizationKind,
                block: "val_b0",
                signatures: Set("n0", "n1", "n2", "n3", "n4"),
                ghost_sender: sig_of("n0"),
            }

        qc_init_with_leader
            // Leader n0 proposes in view 0
            .then(qc_proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW))
            .then( all {
                assert(replica_state.get("n0").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .expect(all_invariants)
            // All replicas process the proposal and vote for it (n0 already did!)
            .then(qc_on_proposal("n1", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n1").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(qc_on_proposal("n2", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n2").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(qc_on_proposal("n3", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n3").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(qc_on_proposal("n4", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n4").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(qc_on_proposal("n5", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n5").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
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
                actionTaken' = Observe({ label: "observe" }),
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
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n3"))
            .then(all{
                assert(store_certificate.get("n0").size() == 1),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n4"))
            .then(all{
                assert(store_certificate.get("n0").size() == 2),
                assert(replica_state.get("n0").ghost_last_seen_notarization==0),
                assert(replica_state.get("n0").last_finalized==0),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n5"))
            .then(all{
                assert(store_certificate.get("n0").size() == 2),
                assert(replica_state.get("n0").ghost_last_seen_notarization==0),
                assert(replica_state.get("n0").last_finalized==0),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })

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

            .then(all{
                assert(replica_state.get("n5").view==0),
                assert(replica_state.get("n5").ghost_last_seen_notarization==-1),
                assert(replica_state.get("n5").last_finalized==-1),
                assert(store_certificate.get("n5").size() == 0),
                assert(not(is_view_notarized(0, store_certificate.get("n5")))),
                assert(not(is_view_notarized_votes(0, store_vote.get("n5"), proposal.block))),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(replica_receives_certificate("n5", cert_n0n1n2n3n4))
            .then(all{
                assert(replica_state.get("n5").view==1),
                assert(replica_state.get("n5").ghost_last_seen_notarization==0),
                assert(replica_state.get("n5").last_finalized==0),
                assert(store_certificate.get("n5").size() == 1),
                assert(store_certificate.get("n5").filter(cert=> cert.kind==FinalizationKind).size() == 1),
                assert(is_view_notarized(0, store_certificate.get("n5"))),
                assert(is_view_finalized(0, store_certificate.get("n5"))),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            
            .expect(select_votes(0, NotarizeKind, store_vote.get("n0")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n1")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n2")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n3")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n4")).size()==6)

            .expect(is_view_finalized_votes(0, store_vote.get("n0"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n0"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n1"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n2"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n3"), "val_b0"))
            .expect(is_view_finalized_votes(0, store_vote.get("n4"), "val_b0"))
            .expect(is_view_finalized(0, store_certificate.get("n5")))

            .expect(store_certificate.get("n0").size() == 2)
            .expect(store_certificate.get("n0").filter(cert => cert.kind==FinalizationKind).size() == 1)
            .expect(store_certificate.get("n0").filter(cert => cert.kind==NotarizationKind).size() == 1)
            
            .expect(store_certificate.get("n1").size() == 2)
            .expect(store_certificate.get("n1").filter(cert => cert.kind==FinalizationKind).size() == 1)
            .expect(store_certificate.get("n1").filter(cert => cert.kind==NotarizationKind).size() == 1)
            
            .expect(store_certificate.get("n2").size() == 2)
            .expect(store_certificate.get("n2").filter(cert => cert.kind==FinalizationKind).size() == 1)
            .expect(store_certificate.get("n2").filter(cert => cert.kind==NotarizationKind).size() == 1)
            
            .expect(store_certificate.get("n3").size() == 2)
            .expect(store_certificate.get("n3").filter(cert => cert.kind==FinalizationKind).size() == 1)
            .expect(store_certificate.get("n3").filter(cert => cert.kind==NotarizationKind).size() == 1)
            
            .expect(store_certificate.get("n4").size() == 2)
            .expect(store_certificate.get("n4").filter(cert => cert.kind==FinalizationKind).size() == 1)
            .expect(store_certificate.get("n4").filter(cert => cert.kind==NotarizationKind).size() == 1)
            
            .expect(store_certificate.get("n5").size() == 1)
            .expect(store_certificate.get("n4").filter(cert => cert.kind==FinalizationKind).size() == 1)

            .expect(is_view_notarized(0, store_certificate.get("n0")))
            .expect(is_view_notarized(0, store_certificate.get("n1")))
            .expect(is_view_notarized(0, store_certificate.get("n2")))
            .expect(is_view_notarized(0, store_certificate.get("n3")))
            .expect(is_view_notarized(0, store_certificate.get("n4")))
            .expect(is_view_notarized(0, store_certificate.get("n5")))

            .expect(is_view_finalized(0, store_certificate.get("n0")))
            .expect(is_view_finalized(0, store_certificate.get("n1")))
            .expect(is_view_finalized(0, store_certificate.get("n2")))
            .expect(is_view_finalized(0, store_certificate.get("n3")))
            .expect(is_view_finalized(0, store_certificate.get("n4")))
            .expect(is_view_finalized(0, store_certificate.get("n5")))

            .expect(all_invariants)

            .then(all {
                assert(ghost_committed_blocks.get("n0") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n1") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n2") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n3") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n4") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n5") == ["val_b0"]),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all,
            })

            .then(all {
                assert(replica_state.get("n0").view == 1),
                assert(replica_state.get("n1").view == 1),
                assert(replica_state.get("n2").view == 1),
                assert(replica_state.get("n3").view == 1),
                assert(replica_state.get("n4").view == 1),
                assert(replica_state.get("n5").view == 1),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all,
            })

            .then(all {
                assert(replica_state.get("n0").ghost_last_seen_notarization == 0),
                assert(replica_state.get("n1").ghost_last_seen_notarization == 0),
                assert(replica_state.get("n2").ghost_last_seen_notarization == 0),
                assert(replica_state.get("n3").ghost_last_seen_notarization == 0),
                assert(replica_state.get("n4").ghost_last_seen_notarization == 0),
                assert(replica_state.get("n5").ghost_last_seen_notarization == 0),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all,
            })

            .then(all {
                assert(replica_state.get("n0").last_finalized == 0),
                assert(replica_state.get("n1").last_finalized == 0),
                assert(replica_state.get("n2").last_finalized == 0),
                assert(replica_state.get("n3").last_finalized == 0),
                assert(replica_state.get("n4").last_finalized == 0),
                assert(replica_state.get("n5").last_finalized == 0),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all,
            })

            .expect(all_invariants)
    }

    run happyPathWithNotarizationCertificatesTest = {
        val proposal = {
            block: "val_b0",
            view: 0,
            view_parent: GENESIS_VIEW,
            block_parent: GENESIS_BLOCK,
            sig: sig_of("n0")
        }

        val n4_vote = {
            view: 0,
            block: "val_b0",
            sig: sig_of("n4"),
            kind: NotarizeKind
        }

        val n5_vote = {
            view: 0,
            block: "val_b0",
            sig: sig_of("n5"),
            kind: NotarizeKind
        }

        val cert_n0n1n2 = {
            view: 0,
            kind: NotarizationKind,
            block: "val_b0",
            signatures: Set("n0", "n1", "n2"),
            ghost_sender: sig_of("n0"),
        }


        qc_init_with_leader
            // Leader n0 proposes in view 0
            .then(qc_proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW))
            .then( all {
                assert(replica_state.get("n0").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .expect(all_invariants)
            // replicas n0-n4, but not n5 process the proposal and vote for it (n0 already did!)
            .then(qc_on_proposal("n1", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n1").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(qc_on_proposal("n2", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n2").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(qc_on_proposal("n3", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n3").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })

            
            .expect(all_invariants)

            // All replicas collect votes and notarize the block
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n3"))

            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n3"))

            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n3"))


            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n3"))

            .then(all{
                assert(not(sent_vote.contains(n4_vote))),
                assert(store_vote.get("n4").filter(v=>v.view==0 and v.kind==NotarizeKind and v.block == "val_b0").size() == 0),
                assert(store_certificate.get("n4").size() == 0),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(replica_receives_certificate("n4", cert_n0n1n2))
            // since n4 did not vote for the block it must send it's vote now
            .then(all{
                assert(store_certificate.get("n4").size() == 1),
                assert(sent_vote.contains(n4_vote)),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })


            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n1"))
            .then(all{
                assert(not(sent_vote.contains(n5_vote))),
                assert(store_vote.get("n5").filter(v=>v.view==0 and v.kind==NotarizeKind and v.block == "val_b0").size() == 2),
                assert(store_certificate.get("n5").size() == 0),
                assert(not(is_view_notarized(0, store_certificate.get("n5")))),
                assert(replica_state.get("n5").ghost_sent_votes.get(0).length() == 0),
                assert(replica_state.get("n5").notarized.get(0) == EMPTY_BLOCK),
                assert(not(replica_state.get("n5").has_notarized())),
                assert(replica_state.get("n5").view == 0),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n2"))
            // n5 has votes and M-quorum. 
            // since n5 did not vote for the block it must send its vote now and add M-notarization (certificate)
            .then(all{
                assert(store_certificate.get("n5").size() == 1),
                assert(sent_vote.contains(n5_vote)),
                assert(replica_state.get("n5").ghost_sent_votes.get(0).length() == 1),
                assert(replica_state.get("n5").notarized.get(0) == "val_b0"),
                assert(replica_state.get("n5").view == 1),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            // n5 receives another vote. It should be in new view now, so no votes for previous view or new certificates.
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n3"))
            .then(all{
                assert(store_certificate.get("n5").size() == 1),
                assert(is_view_notarized(0, store_certificate.get("n5"))),
                assert(replica_state.get("n5").ghost_sent_votes.get(0).length() == 1),
                assert(replica_state.get("n5").ghost_sent_votes.get(1).length() == 0),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n4"))
            .then(all{
                assert(store_certificate.get("n5").size() == 2),
                assert(is_view_finalized_votes(0, store_vote.get("n5"), "val_b0")),
                assert(replica_state.get("n5").ghost_sent_votes.get(0).length() == 1),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })

            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n4"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n4"))

            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n5"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n5"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n5"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n5"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n5"))
            .then(replica_receives_notarize_vote("n5", "val_b0", 0, "n5"))

            .expect(select_votes(0, NotarizeKind, store_vote.get("n0")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n1")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n2")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n3")).size()==6)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n4")).size()==2)
            .expect(select_votes(0, NotarizeKind, store_vote.get("n5")).size()==6)

            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n0"))  
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n1"))  
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n2"))  
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n3"))            
            .expect(select_votes(0, NotarizeKind, store_vote.get("n4")).size()==6)

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
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all,
            })

            .then(all {
                assert(replica_state.get("n0").view == 1),
                assert(replica_state.get("n1").view == 1),
                assert(replica_state.get("n2").view == 1),
                assert(replica_state.get("n3").view == 1),
                assert(replica_state.get("n4").view == 1),
                assert(replica_state.get("n5").view == 1),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all,
            })

            .then(all {
                assert(ghost_committed_blocks.get("n0") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n1") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n2") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n3") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n4") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n5") == ["val_b0"]),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all,
            })
            
    }

    run happyPathWithFinalizationTest = {
        val proposal = {
            block: "val_b0",
            view: 0,
            view_parent: GENESIS_VIEW,
            block_parent: GENESIS_BLOCK,
            sig: sig_of("n0")
        }

        val n5_vote = {
            view: 0,
            block: "val_b0",
            sig: sig_of("n5"),
            kind: NotarizeKind
        }

        val notarization_n0n1n2 = {
            view: 0,
            kind: NotarizationKind,
            block: "val_b0",
            signatures: Set("n0", "n1", "n2"),
            ghost_sender: sig_of("n0"),
        }

        val finalization_n0n1n2n3n4 = {
            view: 0,
            kind: FinalizationKind,
            block: "val_b0",
            signatures: Set("n0", "n1", "n2", "n3", "n4"),
            ghost_sender: sig_of("n0"),
        }


        qc_init_with_leader
            // Leader n0 proposes in view 0
            .then(qc_proposer_step("n0", "val_b0", GENESIS_BLOCK, GENESIS_VIEW))
            .then( all {
                assert(replica_state.get("n0").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .expect(all_invariants)
            // replicas n0-n4, but not n5 process the proposal and vote for it (n0 already did!)
            .then(qc_on_proposal("n1", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n1").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(qc_on_proposal("n2", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n2").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(qc_on_proposal("n3", proposal, "n0"))
            .then( all {
                assert(replica_state.get("n3").notarized.get(0)=="val_b0"),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            
            .expect(all_invariants)

            // All replicas collect votes and notarize the block
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n0", "val_b0", 0, "n4"))

            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n1", "val_b0", 0, "n4"))

            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n2", "val_b0", 0, "n4"))

            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n3", "val_b0", 0, "n4"))

            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n0"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n1"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n2"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n3"))
            .then(replica_receives_notarize_vote("n4", "val_b0", 0, "n4"))

            .then(all{
                assert(not(sent_vote.contains(n5_vote))),
                assert(store_vote.get("n5").filter(v=>v.view==0 and v.kind==NotarizeKind and v.block == "val_b0").size() == 0),
                assert(store_certificate.get("n5").size() == 0),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            .then(replica_receives_certificate("n5", notarization_n0n1n2))
    
            // since n4 did not vote for the block it must send it's vote now
            .then(all{
                assert(store_certificate.get("n5").size() == 1),
                assert(sent_vote.contains(n5_vote)),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })

            .then(replica_receives_certificate("n5", finalization_n0n1n2n3n4))
            .then(all{
                assert(store_certificate.get("n5").size() == 2),
                assert(sent_vote.contains(n5_vote)),
                assert(replica_state.get("n5").ghost_sent_votes.get(0).length() == 1),
                assert(replica_state.get("n5").notarized.get(0) == "val_b0"),
                assert(replica_state.get("n5").view == 1),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all
            })
            
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
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all,
            })

            .then(all {
                assert(replica_state.get("n0").view == 1),
                assert(replica_state.get("n1").view == 1),
                assert(replica_state.get("n2").view == 1),
                assert(replica_state.get("n3").view == 1),
                assert(replica_state.get("n4").view == 1),
                assert(replica_state.get("n5").view == 1),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all,
            })

            .then(all {
                assert(ghost_committed_blocks.get("n0") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n1") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n2") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n3") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n4") == ["val_b0"]),
                assert(ghost_committed_blocks.get("n5") == ["val_b0"]),
                actionTaken' = Observe({ label: "observe" }),
                unchanged_all,
            })
    }

    // Two blocks happy path test - commits blocks in views 1 and 2


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
    
    action replica_receives_certificate(id: ReplicaId, cert: Certificate): bool =
        all {
            on_certificate(id, cert),
            actionTaken' = ReplicaReceivesCertificate({
                id: id,
                kind: cert.kind,
                block: cert.block,
                view: cert.view,
                signatures: cert.signatures,
                ghost_sender: cert.ghost_sender,
            }),
        }

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
