module pictor_network::pictor_network {
    use std::string;
    use std::signer;
    use std::vector;
    use std::string::String;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;

    use pictor_network::package_manager;
    use pictor_network::pictor_config;

    const MODULE_NAME: vector<u8> = b"PICTOR_NETWORK";
    const ENOT_AUTHORIZED: u64 = 1;
    const ENOT_INITIALIZED: u64 = 2;
    const EUSER_NOT_REGISTERED: u64 = 3;
    const EWORKER_NOT_REGISTERED: u64 = 4;
    const EWORKER_REGISTERED: u64 = 5;

    struct SignerConfig has store, key {
        signer_cap: SignerCapability
    }

    struct GlobalConfig has key, store {
        treasury_addr: address,
        worker_earning_percentage: u64
    }

    struct UserInfo has key, store {
        balance: u64,
        credit: u64,
        workers: vector<String>
    }

    struct Worker has store {
        owner: address
    }

    struct Task has store {
        task_id: u64,
        worker_id: String,
        cost: u64,
        duration: u64
    }

    struct Job has store {
        owner: address,
        tasks: vector<Task>,
        payment: u64,
        is_completed: bool
    }

    public fun initialize(owner: &signer, treasury_addr: address) {
        assert!(signer::address_of(owner) == @deployer, ENOT_AUTHORIZED);
        if (is_initialized()) { return };
        pictor_config::initialize(treasury_addr);
        let (module_signer, signer_cap) =
            account::create_resource_account(
                &package_manager::get_signer(), MODULE_NAME
            );
        move_to(&module_signer, SignerConfig { signer_cap });
        package_manager::add_address(
            string::utf8(MODULE_NAME), signer::address_of(&module_signer)
        )
    }

    public entry fun register_user(user: &signer) {
        let user_address = signer::address_of(user);
        if (exists<UserInfo>(user_address)) {
            return;
        };
        move_to(
            user,
            UserInfo {
                balance: 0,
                credit: 0,
                workers: vector::empty<String>()
            }
        );
    }

    public entry fun register_worker(user: &signer, worker_id: String) acquires UserInfo {
        let user_address = signer::address_of(user);
        assert!(exists<UserInfo>(user_address), 0x1);
        let user_info = borrow_global_mut<UserInfo>(user_address);
        assert!(!vector::contains(&user_info.workers, &worker_id), EWORKER_REGISTERED);
        vector::push_back(&mut user_info.workers, worker_id);
    }

    public entry fun op_register_worker(
        operator: &signer, user_addr: address, worker_id: String
    ) acquires UserInfo {
        assert!(
            pictor_config::is_operator(signer::address_of(operator)), ENOT_AUTHORIZED
        );
        assert!(exists<UserInfo>(user_addr), EUSER_NOT_REGISTERED);
        let user_info = borrow_global_mut<UserInfo>(user_addr);
        assert!(!vector::contains(&user_info.workers, &worker_id), EWORKER_REGISTERED);
        vector::push_back(&mut user_info.workers, worker_id);
    }

    #[view]
    public fun get_user_info(user: address): (u64, u64) acquires UserInfo {
        let userInfo = borrow_global<UserInfo>(user);
        (userInfo.balance, userInfo.credit)
    }

    #[view]
    public fun is_worker_registered(user: address, worker_id: String): bool acquires UserInfo {
        assert!(exists<UserInfo>(user), EUSER_NOT_REGISTERED);
        let user_info = borrow_global<UserInfo>(user);
        vector::contains(&user_info.workers, &worker_id)
    }

    #[view]
    public fun is_initialized(): bool {
        package_manager::address_exists(string::utf8(MODULE_NAME))
    }
}
