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
    const EINITIALIZED: u64 = 0;
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
        workers: Table<String, address>,
        users: Table<address, UserInfo>
    }

    struct UserInfo has key, store {
        balance: u64,
        credit: u64,
        jobs: Table<String, Job>
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

    public entry fun initialize(owner: &signer, treasury_addr: address) {
        assert!(signer::address_of(owner) == @deployer, ENOT_AUTHORIZED);
        assert!(!is_initialized(), EINITIALIZED);
        pictor_config::initialize(treasury_addr);
        let (module_signer, signer_cap) =
            account::create_resource_account(
                &package_manager::get_signer(), MODULE_NAME
            );
        move_to(&module_signer, SignerConfig { signer_cap });
        move_to(
            &module_signer,
            GlobalData {
                workers: table::new<String, address>(),
                users: table::new<address, UserInfo>()
            }
        );
        package_manager::add_address(
            string::utf8(MODULE_NAME), signer::address_of(&module_signer)
        )
    }

    public entry fun register_user(user: &signer) acquires GlobalData {
        let user_address = signer::address_of(user);
        assert!(is_initialized(), ENOT_INITIALIZED);
        register_user_internal(user_address);
    }

    public entry fun register_worker(user: &signer, worker_id: String) acquires GlobalData {
        assert!(is_initialized(), ENOT_INITIALIZED);
        register_worker_internal(signer::address_of(user), worker_id);
    }

    public entry fun op_register_worker(
        operator: &signer, user_addr: address, worker_id: String
    ) acquires GlobalData {
        assert_is_operator(operator);
        register_worker_internal(user_addr, worker_id);
    }

    public entry fun op_create_job(
        operator: &signer, user_addr: address, job_id: String
    ) acquires GlobalData {
        assert_is_operator(operator);
        register_user_internal(user_addr);

        let user_info = mut_user_info(user_addr);
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
    ) acquires GlobalData {
        assert_is_operator(operator);
        assert_job_created(user_addr, job_id);

        let user_info = mut_user_info(user_addr);

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
    ) acquires GlobalData {
        assert_is_operator(operator);
        assert_job_created(user_addr, job_id);

        let global = mut_global_data();

        let user_info = table::borrow_mut<address, UserInfo>(
            &mut global.users, user_addr
        );
        let job = table::borrow_mut(&mut user_info.jobs, job_id);
        job.is_completed = true;

        let worker_percentage = pictor_config::get_worker_earning_percentage();
        let denominator = pictor_config::get_denominator();

        let i = vector::length(&job.tasks);
        while (i > 0) {
            i = i - 1;
            let user_info = table::borrow<address, UserInfo>(
                &mut global.users, user_addr
            );
            let job = table::borrow(&user_info.jobs, job_id);
            let task = vector::borrow(&job.tasks, i);
            let cost = task.cost;
            let owner_addr =
                table::borrow<String, address>(&global.workers, task.worker_id);

            // Add payment to worker's owner
            let owner_info =
                table::borrow_mut<address, UserInfo>(&mut global.users, *owner_addr);
            owner_info.balance = owner_info.balance
                + cost * worker_percentage / denominator;
        };
    }

    public entry fun op_credit_user(
        operator: &signer, user_addr: address, amount: u64
    ) acquires GlobalData {
        assert_is_operator(operator);
        register_user_internal(user_addr);

        let user_info = mut_user_info(user_addr);
        user_info.credit = user_info.credit + amount;
    }

    public entry fun op_debit_user(
        operator: &signer, user_addr: address, amount: u64
    ) acquires GlobalData {
        assert_is_operator(operator);
        assert_user_registered(user_addr);

        let user_info = mut_user_info(user_addr);
        assert!(
            user_info.credit >= amount,
            EInsufficentBalance
        );
        user_info.credit = user_info.credit - amount;
    }

    inline fun get_global_data(): &GlobalData acquires GlobalData {
        borrow_global<GlobalData>(package_manager::get_address(string::utf8(MODULE_NAME)))
    }

    inline fun mut_global_data(): &mut GlobalData acquires GlobalData {
        borrow_global_mut<GlobalData>(
            package_manager::get_address(string::utf8(MODULE_NAME))
        )
    }

    inline fun get_user_info(user_addr: address): &UserInfo acquires GlobalData {
        let global = get_global_data();
        table::borrow<address, UserInfo>(&global.users, user_addr)
    }

    inline fun mut_user_info(user_addr: address): &mut UserInfo acquires GlobalData {
        let global = mut_global_data();
        table::borrow_mut<address, UserInfo>(&mut global.users, user_addr)
    }

    #[view]
    public fun get_user_balance(user_addr: address): (u64, u64) acquires GlobalData {
        let user_info = get_user_info(user_addr);
        (user_info.balance, user_info.credit)
    }

    #[view]
    public fun get_worker_owner(worker_id: String): address acquires GlobalData {
        let global = get_global_data();
        let owner_addr = table::borrow(&global.workers, worker_id);
        *owner_addr
    }

    #[view]
    public fun get_job_info(user_addr: address, job_id: String): (u64, u64, bool) acquires GlobalData {
        let user_info = get_user_info(user_addr);
        assert!(
            table::contains<String, Job>(&user_info.jobs, job_id),
            EJOB_NOT_FOUND
        );
        let job = table::borrow(&user_info.jobs, job_id);
        (vector::length<Task>(&job.tasks), job.payment, job.is_completed)
    }

    #[view]
    public fun get_job_info_by_worker(
        user_addr: address, job_id: String, worker_id: String
    ): (u64, u64, bool) acquires GlobalData {
        let user_info = get_user_info(user_addr);
        assert!(
            table::contains<String, Job>(&user_info.jobs, job_id),
            EJOB_NOT_FOUND
        );
        let job = table::borrow(&user_info.jobs, job_id);
        let worker_percentage = pictor_config::get_worker_earning_percentage();
        let denominator = pictor_config::get_denominator();
        let task_count = 0;
        let payment = 0;
        let i = vector::length(&job.tasks);
        while (i > 0) {
            i = i - 1;
            let task = vector::borrow(&job.tasks, i);

            if (task.worker_id == worker_id) {
                task_count = task_count + 1;
                payment = payment + task.cost;
            }
        };

        (task_count, payment * worker_percentage / denominator, job.is_completed)
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

    fun assert_user_registered(user_addr: address) acquires GlobalData {
        let global = get_global_data();
        assert!(
            table::contains<address, UserInfo>(&global.users, user_addr),
            EUSER_NOT_REGISTERED
        );
    }

    fun assert_job_created(user_addr: address, job_id: String) acquires GlobalData {
        let global = get_global_data();
        let user_info = table::borrow<address, UserInfo>(&global.users, user_addr);
        assert!(
            table::contains<String, Job>(&user_info.jobs, job_id),
            EJOB_NOT_FOUND
        );
    }

    fun register_user_internal(user_addr: address) acquires GlobalData {
        let global = mut_global_data();
        if (!table::contains<address, UserInfo>(&global.users, user_addr)) {
            table::add(
                &mut global.users,
                user_addr,
                UserInfo {
                    balance: 0,
                    credit: 0,
                    jobs: table::new<String, Job>()
                }
            );
        }
    }

    fun register_worker_internal(user_addr: address, worker_id: String) acquires GlobalData {
        register_user_internal(user_addr);
        let global = mut_global_data();
        if (!table::contains<String, address>(&global.workers, worker_id)) {
            table::add(&mut global.workers, worker_id, user_addr);
        }
    }
}
