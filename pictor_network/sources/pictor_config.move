module pictor_network::pictor_config {
    use std::signer;
    use std::signer::address_of;
    use std::string;
    // use std::vector;

    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;

    use pictor_network::package_manager;
    use pictor_network::pictor_network;

    const MODULE_NAME: vector<u8> = b"MANAGER";

    /// Not authorized to perform this action
    const ENOT_AUTHORIZED: u64 = 1;

    struct SignerConfig has store, key {
        signer_cap: SignerCapability
    }

    struct Config has store, key {
        operator: address,
        is_pause: bool,
        treasury_addr: address,
        worker_earning_percentage: u64,
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

    public entry fun initialize<CoinType>(
        owner: &signer, treasury_addr: address
    ) {
        assert!(address_of(owner) == @deployer, ENOT_AUTHORIZED);
        pictor_network::initialize(treasury_addr);
        if (is_initialized()) { return };
        let (module_signer, signer_cap) =
            account::create_resource_account(
                &package_manager::get_signer(), MODULE_NAME
            );
        move_to(&module_signer, SignerConfig { signer_cap });

        move_to(
            &module_signer,
            Config {
                operator: signer::address_of(owner),
                is_pause: false,
                treasury_addr,
                worker_earning_percentage: 6000
            }
        );
        package_manager::add_address(
            string::utf8(MODULE_NAME), signer::address_of(&module_signer)
        )
    }

    public entry fun set_operator(owner: &signer, new_operatorer: address) acquires Config {
        let config = unchecked_config();
        assert!(address_of(owner) == @deployer, ENOT_AUTHORIZED);
        config.operator = new_operatorer;
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
}
