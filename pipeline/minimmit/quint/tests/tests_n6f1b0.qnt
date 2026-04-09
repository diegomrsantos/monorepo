module tests {
    import tests_n6f1b0_basic.asuumptionsValidTest from "./tests_n6f1b0_basic"
    import tests_n6f1b0_basic.initTest from "./tests_n6f1b0_basic"
    import tests_n6f1b0_basic.minimalProposalTest from "./tests_n6f1b0_basic"
    import tests_n6f1b0_basic.happyPathTest from "./tests_n6f1b0_basic"

    import tests_n6f1b0_certificates.n5NodeIsSlowAndGetFinalizationFirstTest from "./tests_n6f1b0_certificates"
    import tests_n6f1b0_certificates.happyPathWithNotarizationCertificatesTest from "./tests_n6f1b0_certificates"
    import tests_n6f1b0_certificates.happyPathWithFinalizationTest from "./tests_n6f1b0_certificates"

    import tests_n6f1b0_blocks.twoBlocksTest from "./tests_n6f1b0_blocks"
    import tests_n6f1b0_blocks.twoBlocksDifferentViewsTest from "./tests_n6f1b0_blocks"

    import tests_n6f1b0_failures.timeoutTest from "./tests_n6f1b0_failures"
    import tests_n6f1b0_failures.nullificationTest from "./tests_n6f1b0_failures"
    import tests_n6f1b0_failures.contradictionTest from "./tests_n6f1b0_failures"
}
