module pictor_network::pictor_network {
    use std::string;
    use std::signer;
    use std::vector;
    use std::string::String;
    use aptos_std::table::{Self, Table};
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
    const EJOB_NOT_FOUND: u64 = 6;
    const EJOB_EXISTS: u64 = 7;
    const EInsufficentBalance: u64 = 8;

    struct SignerConfig has store, key {
        signer_cap: SignerCapability
    }

    struct GlobalData has key {
        workers: Table<String, address>
    }

    struct UserInfo has key, store {
        balance: u64,
        credit: u64,
        workers: vector<String>,
        jobs: Table<String, Job>
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
        move_to(
            &module_signer,
            GlobalData {
                workers: table::new<String, address>()
            }
        );
        package_manager::add_address(
            string::utf8(MODULE_NAME), signer::address_of(&module_signer)
        )
    }

    public entry fun register_user(user: &signer) {
        let user_address = signer::address_of(user);
        if (!exists<UserInfo>(user_address)) {
            move_to(
                user,
                UserInfo {
                    balance: 0,
                    credit: 0,
                    workers: vector::empty<String>(),
                    jobs: table::new<String, Job>()
                }
            );
        };
    }

    public entry fun register_worker(user: &signer, worker_id: String) acquires UserInfo, GlobalData {
        register_worker_internal(signer::address_of(user), worker_id);
    }

    public entry fun op_register_worker(
        operator: &signer, user_addr: address, worker_id: String
    ) acquires UserInfo, GlobalData {
        assert_is_operator(operator);
        register_worker_internal(user_addr, worker_id);
    }

    public entry fun op_create_job(
        operator: &signer, user_addr: address, job_id: String
    ) acquires UserInfo {
        assert_is_operator(operator);
        assert_user_registered(user_addr);

        let user_info = borrow_global_mut<UserInfo>(user_addr);
        assert!(
            !table::contains<String, Job>(&user_info.jobs, job_id),
            EJOB_EXISTS
        );

        table::add(
            &mut user_info.jobs,
            job_id,
            Job {
                tasks: vector::empty<Task>(),
                payment: 0,
                is_completed: false
            }
        );
    }

    public entry fun op_add_task(
        operator: &signer,
        user_addr: address,
        job_id: String,
        task_id: u64,
        worker_id: String,
        cost: u64,
        duration: u64
    ) acquires UserInfo {
        assert_is_operator(operator);
        assert_job_created(user_addr, job_id);

        let user_info = borrow_global_mut<UserInfo>(user_addr);

        assert!(
            user_info.credit + user_info.balance >= cost,
            EInsufficentBalance
        );

        // Deduct payment from user, credit first, then balance
        if (user_info.credit >= cost) {
            user_info.credit = user_info.credit - cost;
        } else {
            let remaining_payment = cost - user_info.credit;
            user_info.credit = 0;
            user_info.balance = user_info.balance - remaining_payment;
        };

        let job = table::borrow_mut(&mut user_info.jobs, job_id);
        vector::push_back(
            &mut job.tasks,
            Task { task_id, worker_id, cost, duration }
        );
        job.payment = job.payment + cost;
    }

    public entry fun op_complete_job(
        operator: &signer, user_addr: address, job_id: String
    ) acquires UserInfo, GlobalData {
        assert_is_operator(operator);
        assert_job_created(user_addr, job_id);

        let user_info = borrow_global_mut<UserInfo>(user_addr);
        let job = table::borrow_mut(&mut user_info.jobs, job_id);
        job.is_completed = true;

        let worker_percentage = pictor_config::get_worker_earning_percentage();
        let denominator = pictor_config::get_denominator();

        let global = get_global_data();

        let i = vector::length(&job.tasks);
        while (i > 0) {
            i = i - 1;
            let task = vector::borrow(&job.tasks, i);
            let owner_addr =
                table::borrow<String, address>(&global.workers, task.worker_id);

            // Add payment to worker's owner
            let owner_info = borrow_global_mut<UserInfo>(*owner_addr);
            owner_info.balance =
                owner_info.balance + task.cost * worker_percentage / denominator;
        };
    }

    inline fun get_global_data(): &GlobalData acquires GlobalData {
        borrow_global<GlobalData>(package_manager::get_address(string::utf8(MODULE_NAME)))
    }

    inline fun mut_global_data(): &mut GlobalData acquires GlobalData {
        borrow_global_mut<GlobalData>(
            package_manager::get_address(string::utf8(MODULE_NAME))
        )
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
    public fun get_job_info(user_addr: address, job_id: String): (u64, u64, bool) acquires UserInfo {
        assert_job_created(user_addr, job_id);
        let user_info = borrow_global<UserInfo>(user_addr);
        assert!(
            table::contains<String, Job>(&user_info.jobs, job_id),
            EJOB_NOT_FOUND
        );
        let job = table::borrow(&user_info.jobs, job_id);
        (vector::length<Task>(&job.tasks), job.payment, job.is_completed)
    }

    #[view]
    public fun is_initialized(): bool {
        package_manager::address_exists(string::utf8(MODULE_NAME))
    }

    fun assert_is_operator(operator: &signer) {
        assert!(
            pictor_config::is_operator(signer::address_of(operator)), ENOT_AUTHORIZED
        );
    }

    fun assert_user_registered(user: address) {
        assert!(exists<UserInfo>(user), EUSER_NOT_REGISTERED);
    }

    fun assert_job_created(user_addr: address, job_id: String) acquires UserInfo {
        assert_user_registered(user_addr);
        let user_info = borrow_global<UserInfo>(user_addr);
        assert!(
            table::contains<String, Job>(&user_info.jobs, job_id),
            EJOB_NOT_FOUND
        );
    }

    fun register_worker_internal(user_addr: address, worker_id: String) acquires UserInfo, GlobalData {
        assert_user_registered(user_addr);
        let user_info = borrow_global_mut<UserInfo>(user_addr);
        assert!(!vector::contains(&user_info.workers, &worker_id), EWORKER_REGISTERED);
        vector::push_back(&mut user_info.workers, worker_id);

        let global = mut_global_data();
        if (!table::contains<String, address>(&global.workers, worker_id)) {
            table::add(&mut global.workers, worker_id, user_addr);
        }
    }
}
