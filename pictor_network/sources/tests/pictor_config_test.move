#[test_only]
module pictor_network::pictor_config_test {
    use std::signer;

    use pictor_network::package_manager;
    use pictor_network::pictor_config;
    use pictor_network::pictor_network;

    #[test(admin = @0xcafe)]
    public fun test_initialize(admin: &signer) {
        initialize(admin);
        assert!(pictor_config::is_initialized(), 0x1);
    }

    #[test(admin = @0xcafe, operator = @0xdad)]
    public fun test_add_and_remove_operator(
        admin: &signer, operator: &signer
    ) {
        initialize(admin);
        let operator_addr = signer::address_of(operator);
        pictor_config::add_operator(admin, operator_addr);
        assert!(pictor_config::is_operator(operator_addr), 0x2);
        pictor_config::remove_operator(admin, operator_addr);
        assert!(!pictor_config::is_operator(operator_addr), 0x3);
    }

    fun initialize(admin: &signer) {
        package_manager::initialize_for_test(admin);
        pictor_network::initialize(admin, signer::address_of(admin));
    }
}
