module tests_n6f1b0_params {
    pure val PARAM_N = 6
    pure val PARAM_F = 1
    pure val PARAM_CORRECT = Set("n0", "n1", "n2", "n3", "n4", "n5")
    pure val PARAM_REPLICA_KEYS = Map("n0"->"n0", "n1"->"n1", "n2"->"n2", "n3"->"n3", "n4" -> "n4", "n5"->"n5")
    pure val PARAM_BYZANTINE = Set()
    pure val PARAM_VIEWS = 0.to(5)
    pure val PARAM_VALID_BLOCKS = Set("val_b0", "val_b1", "val_b2")
    pure val PARAM_INVALID_BLOCKS = Set("inv_b3")
}
