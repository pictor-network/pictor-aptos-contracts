#[test_only]
module pictor_network::pictor_config_test {
    use std::signer;

    use pictor_network::pictor_config;
    use pictor_network::test_helper;

    #[test(admin = @0xcafe)]
    public fun test_initialize(admin: &signer) {
        test_helper::setup(admin);
        assert!(pictor_config::is_initialized(), 0x1);
    }

    #[test(admin = @0xcafe, operator = @0xdad)]
    public fun test_add_and_remove_operator(
        admin: &signer, operator: &signer
    ) {
        test_helper::setup(admin);
        let operator_addr = signer::address_of(operator);
        pictor_config::add_operator(admin, operator_addr);
        assert!(pictor_config::is_operator(operator_addr), 0x2);
        pictor_config::remove_operator(admin, operator_addr);
        assert!(!pictor_config::is_operator(operator_addr), 0x3);
    }
}
