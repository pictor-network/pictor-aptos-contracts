module pictor_network::pictor_network {
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;

    use pictor_network::package_manager;
    friend pictor_network::pictor_config;

    const MODULE_NAME: vector<u8> = b"PICTOR_NETWORK";

    struct SignerConfig has store, key {
        signer_cap: SignerCapability
    }

    struct GlobalConfig has key, store {
        treasury_addr: address,
        worker_earning_percentage: u64,
    }

    struct UserInfo has store {
        balance: u64,
        credit: u64,
    }

    struct Worker has store {
        owner: address,
        staked: u64,
        is_active: bool,
    }

    struct Task has store {
        task_id: u64,
        worker_id: String,
        cost: u64,
        duration: u64,
    }

    struct Job has store {
        owner: address,
        tasks: vector<Task>,
        payment: u64,
        is_completed: bool,
    }

    public(friend) fun initialize(treasury_addr: address) {
        if (is_initialized()) {
            return
        };
        let (module_signer, signer_cap) =
            account::create_resource_account(&package_manager::get_signer(), MODULE_NAME);
        move_to(&module_signer, SignerConfig {
            signer_cap
        });
        move_to(&module_signer, GlobalConfig {
            treasury_addr,
            worker_earning_percentage: 6000
        });
        package_manager::add_address(string::utf8(MODULE_NAME), signer::address_of(&module_signer))
    }

    #[view]
    public fun is_initialized(): bool {
        package_manager::address_exists(string::utf8(MODULE_NAME))
    }

}

