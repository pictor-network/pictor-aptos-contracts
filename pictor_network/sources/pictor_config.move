module pictor_network::pictor_config {
    use std::signer;
    use std::signer::address_of;
    use std::string;
    use std::vector;
    use aptos_std::table::{Self, Table};

    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, FungibleAsset, FungibleStore, Metadata};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;

    use pictor_network::package_manager;
    friend pictor_network::pictor_network;

    const DENOMINATOR: u64 = 10000;

    const MODULE_NAME: vector<u8> = b"PICTOR_CONFIG";
    const EINITIALIZED: u64 = 0;
    const ENOT_AUTHORIZED: u64 = 1;
    const ENOT_INITIALIZED: u64 = 2;
    const EOPERATOR_EXISTS: u64 = 3;
    const ENOT_SUPPORTED_TOKEN: u64 = 4;

    struct SignerConfig has store, key {
        signer_cap: SignerCapability
    }

    struct Config has store, key {
        operators: vector<address>,
        is_pause: bool,
        treasury_addr: address,
        worker_earning_percentage: u64,
        admin_pubkey: vector<u8>,
        vault: Table<Object<Metadata>, Object<FungibleStore>>
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

    public entry fun initialize(
        owner: &signer,
        payment_token: Object<Metadata>,
        treasury_addr: address,
        admin_pubkey: vector<u8>
    ) {
        assert!(signer::address_of(owner) == @deployer, ENOT_AUTHORIZED);
        assert!(!is_initialized(), EINITIALIZED);
        let (module_signer, signer_cap) =
            account::create_resource_account(
                &package_manager::get_signer(), MODULE_NAME
            );
        move_to(&module_signer, SignerConfig { signer_cap });

        let constructor_ref = &object::create_object(signer::address_of(&module_signer));
        let store = fungible_asset::create_store(constructor_ref, payment_token);
        let vault = table::new<Object<Metadata>, Object<FungibleStore>>();
        table::add(&mut vault, payment_token, store);

        move_to(
            &module_signer,
            Config {
                operators: vector::empty<address>(),
                is_pause: false,
                treasury_addr,
                worker_earning_percentage: 6000,
                admin_pubkey,
                vault
            }
        );
        package_manager::add_address(
            string::utf8(MODULE_NAME), signer::address_of(&module_signer)
        )
    }

    public entry fun set_admin_pubkey(
        owner: &signer, new_admin_pub: vector<u8>
    ) acquires Config {
        assert!(address_of(owner) == @deployer, ENOT_AUTHORIZED);
        let config = unchecked_config();
        config.admin_pubkey = new_admin_pub;
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

    public entry fun withdraw_to_treasury(
        operator: &signer, amount: u64, token: Object<Metadata>
    ) acquires Config, SignerConfig {
        assert!(
            is_operator(signer::address_of(operator)),
            ENOT_AUTHORIZED
        );
        assert_token_supported(token);

        let store = get_vault_store(token);

        // Withdraw from vault
        let fungible_token =
            dispatchable_fungible_asset::withdraw(&get_signer(), *store, amount);
        primary_fungible_store::deposit(get_treasury_address(), fungible_token);
    }

    public(friend) fun deposit_vault(
        asset: FungibleAsset, token: Object<Metadata>
    ) acquires Config {
        let store = get_vault_store(token);
        dispatchable_fungible_asset::deposit(*store, asset);
    }

    public(friend) fun withdraw_vault(
        amount: u64, token: Object<Metadata>
    ): FungibleAsset acquires Config, SignerConfig {
        let store = get_vault_store(token);
        dispatchable_fungible_asset::withdraw(&get_signer(), *store, amount)
    }

    inline fun unchecked_config(): &mut Config {
        borrow_global_mut<Config>(storage_address())
    }

    inline fun get_config(): &Config {
        borrow_global<Config>(storage_address())
    }

    inline fun get_vault_store(token: Object<Metadata>): &Object<FungibleStore> acquires Config {
        let config = get_config();
        assert!(
            table::contains<Object<Metadata>, Object<FungibleStore>>(
                &config.vault, token
            ),
            ENOT_SUPPORTED_TOKEN
        );
        table::borrow<Object<Metadata>, Object<FungibleStore>>(&config.vault, token)
    }

    #[view]
    public fun get_admin_pubkey(): vector<u8> acquires Config {
        get_config().admin_pubkey
    }

    // Get treasury address
    #[view]
    public fun get_treasury_address(): address acquires Config {
        get_config().treasury_addr
    }

    #[view]
    public fun is_operator(addr: address): bool acquires Config {
        let config = get_config();
        vector::contains(&config.operators, &addr)
    }

    #[view]
    public fun get_denominator(): u64 {
        DENOMINATOR
    }

    #[view]
    public fun get_worker_earning_percentage(): u64 acquires Config {
        get_config().worker_earning_percentage
    }

    #[view]
    public fun get_vault_balance(token: Object<Metadata>): u64 acquires Config {
        let store = get_vault_store(token);
        fungible_asset::balance(*store)
    }

    fun assert_token_supported(token: Object<Metadata>) acquires Config {
        let config = get_config();
        assert!(
            table::contains<Object<Metadata>, Object<FungibleStore>>(
                &config.vault, token
            ),
            ENOT_SUPPORTED_TOKEN
        );
    }

    fun get_signer(): signer acquires SignerConfig {
        let signer_config =
            borrow_global<SignerConfig>(
                package_manager::get_address(string::utf8(MODULE_NAME))
            );
        account::create_signer_with_capability(&signer_config.signer_cap)
    }
}
