#[test_only]
module pictor_network::pictor_network_test {
    use std::signer;
    use std::string;
    use aptos_framework::primary_fungible_store;

    use pictor_network::pictor_config;
    use pictor_network::pictor_network;
    use pictor_network::usdt;
    use pictor_network::test_helper;

    #[test(admin = @0xcafe, operator = @0xdad)]
    public fun test_initialize(admin: &signer) {
        test_helper::setup(admin);
        assert!(pictor_network::is_initialized(), 0x1);
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_register_user(admin: &signer, user: &signer) {
        test_helper::setup(admin);
        pictor_network::register_user(user);
        let user_addr = signer::address_of(user);
        let (balance, credit) = pictor_network::get_user_balance(user_addr);
        assert!(balance == 0 && credit == 0, 0x2);
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_register_worker(admin: &signer, user: &signer) {
        test_helper::setup(admin);
        pictor_network::register_user(user);
        let user_addr = signer::address_of(user);
        pictor_network::register_worker(user, string::utf8(b"worker1"));
        assert!(
            pictor_network::get_worker_owner(string::utf8(b"worker1")) == user_addr,
            0x3
        );
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_op_register_worker(
        admin: &signer, operator: &signer, user: &signer
    ) {
        test_helper::setup(admin);
        pictor_config::add_operator(admin, signer::address_of(operator));
        let user_addr = signer::address_of(user);
        let worker_id = string::utf8(b"worker1");
        pictor_network::register_user(user);
        pictor_network::op_register_worker(operator, user_addr, worker_id);

        assert!(
            pictor_network::get_worker_owner(string::utf8(b"worker1")) == user_addr,
            0x3
        );
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_op_create_job(
        admin: &signer, operator: &signer, user: &signer
    ) {
        test_helper::setup(admin);
        pictor_config::add_operator(admin, signer::address_of(operator));
        let user_addr = signer::address_of(user);
        let worker_id = string::utf8(b"worker1");
        let job_id = string::utf8(b"job1");
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
        test_helper::setup(admin);
        pictor_config::add_operator(admin, signer::address_of(operator));
        let user_addr = signer::address_of(user);
        let worker_id = string::utf8(b"worker1");
        let job_id = string::utf8(b"job1");
        let task_id = 1;
        let task_cost = 100;
        let task_duration = 10;
        pictor_network::register_user(user);
        pictor_network::op_register_worker(operator, user_addr, worker_id);
        pictor_network::op_create_job(operator, user_addr, job_id);
        pictor_network::op_credit_user(operator, user_addr, task_cost);
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

        let percentage = pictor_config::get_worker_earning_percentage();
        let denominator = pictor_config::get_denominator();

        let (worker_task_count, worker_task_payment, is_completed) =
            pictor_network::get_job_info_by_worker(user_addr, job_id, worker_id);
        assert!(
            worker_task_count == 1
                && worker_task_payment == task_cost * percentage / denominator
                && !is_completed,
            0x3
        );
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun op_credit_and_debit_user(
        admin: &signer, operator: &signer, user: &signer
    ) {
        test_helper::setup(admin);
        pictor_config::add_operator(admin, signer::address_of(operator));
        let user_addr = signer::address_of(user);
        pictor_network::register_user(user);

        let value = 100;

        pictor_network::op_credit_user(operator, user_addr, value);

        let (balance, credit) = pictor_network::get_user_balance(user_addr);

        assert!(balance == 0 && credit == value, 0x2);

        pictor_network::op_debit_user(operator, user_addr, value);

        let (balance_after, credit_after) = pictor_network::get_user_balance(user_addr);

        assert!(balance_after == 0 && credit_after == 0, 0x3);
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_deposit_and_withdraw(
        admin: &signer, operator: &signer, user: &signer
    ) {
        test_helper::setup(admin);
        pictor_config::add_operator(admin, signer::address_of(operator));
        let user_addr = signer::address_of(user);
        pictor_network::register_user(user);
        let deposit_amount = 1000;
        test_helper::mint_usdt(user_addr, deposit_amount);
        pictor_network::deposit(user, deposit_amount, usdt::metadata());

        let (balance, credit) = pictor_network::get_user_balance(user_addr);
        assert!(balance == 0 && credit == deposit_amount, 0x2);

        let usdt_balance = primary_fungible_store::balance(user_addr, usdt::metadata());
        assert!(usdt_balance == 0, 0x3);

        let usdt_balance_after =
            primary_fungible_store::balance(user_addr, usdt::metadata());
        assert!(usdt_balance_after == 0, 0x5);

        let vault_balance = pictor_config::get_vault_balance(usdt::metadata());
        assert!(vault_balance == 1000, 0x6);

        pictor_config::withdraw_to_treasury(operator, 1000, usdt::metadata());
        let admin_balance =
            primary_fungible_store::balance(signer::address_of(admin), usdt::metadata());
        assert!(admin_balance == 1000, 0x7);
    }

    #[test(admin = @0xcafe, operator = @0xdad, user = @0xdead)]
    public fun test_claim_credit(
        admin: &signer, operator: &signer, user: &signer
    ) {
        test_helper::setup(admin);
        pictor_config::add_operator(admin, signer::address_of(operator));
        let user_addr = signer::address_of(user);

        let claim_amount = 1000;

        pictor_network::claim_credit(
            user,
            claim_amount,
            12345,
            vector[
                198, 107, 180, 153, 114, 198, 32, 142, 203, 29, 80, 111, 31, 237, 40, 187,
                193, 149, 164, 167, 158, 78, 33, 113, 100, 81, 46, 123, 29, 184, 148, 144,
                43, 177, 92, 115, 56, 64, 156, 211, 119, 8, 5, 210, 188, 58, 96, 231, 227,
                112, 40, 136, 96, 24, 196, 215, 93, 189, 32, 182, 190, 100, 110, 2
            ]
        );

        let (balance, credit) = pictor_network::get_user_balance(user_addr);
        assert!(balance == 0 && credit == claim_amount, 0x2);

    }
}
