module pictor_network::pictor_network {
    use std::string;
    use std::signer;
    use std::vector;
    use std::string::String;
    use aptos_std::table::{Self, Table};
    use aptos_std::string_utils;
    use aptos_std::ed25519::{
        signature_verify_strict,
        new_signature_from_bytes,
        new_unvalidated_public_key_from_bytes
    };
    use aptos_framework::event;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::object::{Object};
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::primary_fungible_store;

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
    const EINSUFFICENT_BALANCE: u64 = 8;
    const ENOT_SUPPORTED_TOKEN: u64 = 9;
    const ECREDIT_REQUEST_EXISTS: u64 = 10;
    const EINVALID_SIGNATURE: u64 = 11;

    struct SignerConfig has store, key {
        signer_cap: SignerCapability
    }

    struct GlobalData has key {
        workers: Table<String, address>,
        users: Table<address, UserInfo>,
        credit_requests: Table<u64, CreditRequest>
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

    struct CreditRequest has store {
        user_addr: address,
        amount: u64
    }

    #[event]
    struct JobCreated has drop, store {
        user_addr: address,
        job_id: String
    }

    #[event]
    struct TaskAdded has drop, store {
        job_id: String,
        task_id: u64,
        worker_id: String,
        cost: u64
    }

    #[event]
    struct JobCompleted has drop, store {
        job_id: String
    }

    #[event]
    struct CreditClaimed has drop, store {
        user_addr: address,
        amount: u64,
        request_id: u64
    }

    public entry fun initialize(owner: &signer) {
        assert!(signer::address_of(owner) == @deployer, ENOT_AUTHORIZED);
        assert!(!is_initialized(), EINITIALIZED);
        let (module_signer, signer_cap) =
            account::create_resource_account(
                &package_manager::get_signer(), MODULE_NAME
            );
        move_to(&module_signer, SignerConfig { signer_cap });

        move_to(
            &module_signer,
            GlobalData {
                workers: table::new<String, address>(),
                users: table::new<address, UserInfo>(),
                credit_requests: table::new<u64, CreditRequest>()
            }
        );
        package_manager::add_address(
            string::utf8(MODULE_NAME), signer::address_of(&module_signer)
        )
    }

    public entry fun register_user(user: &signer) acquires GlobalData {
        assert!(is_initialized(), ENOT_INITIALIZED);
        let user_address = signer::address_of(user);
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

        event::emit(JobCreated { user_addr, job_id });
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
            EINSUFFICENT_BALANCE
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

        event::emit(TaskAdded { job_id, task_id, worker_id, cost });
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

        event::emit(JobCompleted { job_id });
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
            EINSUFFICENT_BALANCE
        );
        user_info.credit = user_info.credit - amount;
    }

    public entry fun deposit(
        user: &signer, amount: u64, token: Object<Metadata>
    ) acquires GlobalData {
        let user_address = signer::address_of(user);
        register_user_internal(user_address);

        let global = mut_global_data();
        let user_info =
            table::borrow_mut<address, UserInfo>(&mut global.users, user_address);
        user_info.credit = user_info.credit + amount;

        let fungible_token = primary_fungible_store::withdraw(user, token, amount);

        pictor_config::deposit_vault(fungible_token, token);
    }

    public entry fun withdraw(
        user: &signer, amount: u64, token: Object<Metadata>
    ) acquires GlobalData {
        let user_address = signer::address_of(user);
        assert_user_registered(user_address);

        let user_info = mut_user_info(user_address);
        assert!(
            user_info.balance >= amount,
            EINSUFFICENT_BALANCE
        );
        user_info.balance = user_info.balance - amount;

        // Withdraw from vault
        let fungible_token = pictor_config::withdraw_vault(amount, token);
        primary_fungible_store::deposit(signer::address_of(user), fungible_token);
    }

    public entry fun claim_credit(
        user: &signer,
        amount: u64,
        request_id: u64,
        signature: vector<u8>
    ) acquires GlobalData {
        let user_addr = signer::address_of(user);
        register_user_internal(user_addr);
        let global = mut_global_data();
        assert!(
            !table::contains<u64, CreditRequest>(&global.credit_requests, request_id),
            ECREDIT_REQUEST_EXISTS
        );
        let begin_of_mess: String = string::utf8(b"PICTOR\\nmessage: ");
        string::append(&mut begin_of_mess, string_utils::to_string(&amount));
        string::append(&mut begin_of_mess, string_utils::to_string(&request_id));
        string::append(&mut begin_of_mess, string_utils::to_string(&user_addr));
        let upk =
            new_unvalidated_public_key_from_bytes(pictor_config::get_admin_pubkey());

        let check =
            signature_verify_strict(
                &new_signature_from_bytes(signature),
                &upk,
                *string::bytes(&begin_of_mess)
            );
        assert!(check, EINVALID_SIGNATURE);

        let user_info = table::borrow_mut<address, UserInfo>(
            &mut global.users, user_addr
        );
        user_info.credit = user_info.credit + amount;
        table::add(
            &mut global.credit_requests,
            request_id,
            CreditRequest { user_addr, amount }
        );

        event::emit(CreditClaimed { user_addr, amount, request_id });

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
    public fun is_registered(user_addr: address): bool acquires GlobalData {
        let global = get_global_data();
        table::contains<address, UserInfo>(&global.users, user_addr)
    }

    #[view]
    public fun get_user_balance(user_addr: address): (u64, u64) acquires GlobalData {
        if (is_registered(user_addr)) {
            let user_info = get_user_info(user_addr);
            (user_info.balance, user_info.credit)
        } else { (0, 0) }
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
        assert!(
            is_registered(user_addr),
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

    fun get_signer(): signer acquires SignerConfig {
        let signer_config =
            borrow_global<SignerConfig>(
                package_manager::get_address(string::utf8(MODULE_NAME))
            );
        account::create_signer_with_capability(&signer_config.signer_cap)
    }
}
