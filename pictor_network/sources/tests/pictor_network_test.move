#[test_only]
module pictor_network::pictor_network_test {
    use std::signer;
    use std::string;

    use pictor_network::package_manager;
    use pictor_network::pictor_config;
    use pictor_network::pictor_network;

    #[test(admin = @0xcafe, operator = @0xdad)]
    public fun test_initialize(admin: &signer, operator: &signer) {
        initialize(admin, signer::address_of(operator));
        assert!(pictor_network::is_initialized(), 0x1);
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_register_user(
        admin: &signer, operator: &signer, user: &signer
    ) {
        initialize(admin, signer::address_of(operator));
        pictor_network::register_user(user);
        let user_addr = signer::address_of(user);
        let (balance, credit) = pictor_network::get_user_info(user_addr);
        assert!(balance == 0 && credit == 0, 0x2);
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_register_worker(
        admin: &signer, operator: &signer, user: &signer
    ) {
        initialize(admin, signer::address_of(operator));
        pictor_network::register_user(user);
        let user_addr = signer::address_of(user);
        pictor_network::register_worker(user, string::utf8(b"worker1"));
        assert!(
            pictor_network::is_worker_registered(user_addr, string::utf8(b"worker1")),
            0x3
        );
    }

    fun initialize(admin: &signer, operator_addr: address) {
        package_manager::initialize_for_test(admin);
        pictor_network::initialize(admin, signer::address_of(admin));
        pictor_config::add_operator(admin, operator_addr);
    }
}
