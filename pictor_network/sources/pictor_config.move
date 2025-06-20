module pictor_network::pictor_config {
    use std::signer;
    use std::signer::address_of;
    use std::string;
    use std::vector;

    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;

    use pictor_network::package_manager;
    friend pictor_network::pictor_network;

    const MODULE_NAME: vector<u8> = b"MANAGER";
    const ENOT_AUTHORIZED: u64 = 0x1;
    const ENOT_INITIALIZED: u64 = 0x2;
    const EOPERATOR_EXISTS: u64 = 0x3;

    struct SignerConfig has store, key {
        signer_cap: SignerCapability
    }

    struct Config has store, key {
        operators: vector<address>,
        is_pause: bool,
        treasury_addr: address,
        worker_earning_percentage: u64
    }

    #[view]
    public fun is_initialized(): bool {
        package_manager::address_exists(string::utf8(MODULE_NAME))
    }

    #[view]
    public fun storage_address(): address {
        package_manager::get_address(string::utf8(MODULE_NAME))
    }

    inline fun storage_signer(): &signer acquires SignerConfig {
        &account::create_signer_with_capability(
            &borrow_global<SignerConfig>(storage_address()).signer_cap
        )
    }

    public(friend) fun initialize(treasury_addr: address) {
        if (is_initialized()) { return };
        let (module_signer, signer_cap) =
            account::create_resource_account(
                &package_manager::get_signer(), MODULE_NAME
            );
        move_to(&module_signer, SignerConfig { signer_cap });

        move_to(
            &module_signer,
            Config {
                operators: vector::empty<address>(),
                is_pause: false,
                treasury_addr,
                worker_earning_percentage: 6000
            }
        );
        package_manager::add_address(
            string::utf8(MODULE_NAME), signer::address_of(&module_signer)
        )
    }

    public entry fun add_operator(owner: &signer, new_operatorer: address) acquires Config {
        let config = unchecked_config();
        assert!(address_of(owner) == @deployer, ENOT_AUTHORIZED);

        if (!vector::contains(&config.operators, &new_operatorer)) {
            vector::push_back(&mut config.operators, new_operatorer);
        }
    }

    public entry fun remove_operator(owner: &signer, operator: address) acquires Config {
        let config = unchecked_config();
        assert!(address_of(owner) == @deployer, ENOT_AUTHORIZED);

        let (found, index) = vector::index_of(&config.operators, &operator);
        if (found) {
            vector::remove(&mut config.operators, index);
        }
    }

    inline fun unchecked_config(): &mut Config {
        borrow_global_mut<Config>(storage_address())
    }

    inline fun get_config(): &Config {
        borrow_global<Config>(storage_address())
    }

    // Get treasury address
    #[view]
    public fun treasury_addr(): address acquires Config {
        get_config().treasury_addr
    }

    #[view]
    public fun is_operator(addr: address): bool acquires Config {
        let config = get_config();
        vector::contains(&config.operators, &addr)
    }
}
