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

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_op_register_worker(
        admin: &signer, operator: &signer, user: &signer
    ) {
        let user_addr = signer::address_of(user);
        let worker_id = string::utf8(b"worker1");
        initialize(admin, signer::address_of(operator));
        pictor_network::register_user(user);
        pictor_network::op_register_worker(operator, user_addr, worker_id);

        assert!(
            pictor_network::is_worker_registered(user_addr, string::utf8(b"worker1")),
            0x3
        );
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_op_create_job(
        admin: &signer, operator: &signer, user: &signer
    ) {
        let user_addr = signer::address_of(user);
        let worker_id = string::utf8(b"worker1");
        let job_id = string::utf8(b"job1");
        initialize(admin, signer::address_of(operator));
        pictor_network::register_user(user);
        pictor_network::op_register_worker(operator, user_addr, worker_id);
        pictor_network::op_create_job(operator, user_addr, job_id);

        let (tasks, payment, is_completed) =
            pictor_network::get_job_info(user_addr, job_id);

        assert!(tasks == 0 && payment == 0 && !is_completed, 0x2);
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_op_add_task(
        admin: &signer, operator: &signer, user: &signer
    ) {
        let user_addr = signer::address_of(user);
        let worker_id = string::utf8(b"worker1");
        let job_id = string::utf8(b"job1");
        let task_id = 1;
        let task_cost = 100;
        let task_duration = 10;
        initialize(admin, signer::address_of(operator));
        pictor_network::register_user(user);
        pictor_network::op_register_worker(operator, user_addr, worker_id);
        pictor_network::op_create_job(operator, user_addr, job_id);
        pictor_network::op_add_task(
            operator,
            user_addr,
            job_id,
            task_id,
            worker_id,
            task_cost,
            task_duration
        );

        let (tasks, payment, is_completed) =
            pictor_network::get_job_info(user_addr, job_id);

        assert!(
            tasks == 1 && payment == task_cost && !is_completed,
            0x2
        );
    }

    fun initialize(admin: &signer, operator_addr: address) {
        package_manager::initialize_for_test(admin);
        pictor_network::initialize(admin, signer::address_of(admin));
        pictor_config::add_operator(admin, operator_addr);
    }
}
