#[test_only]
module pictor_network::test_helper {
    // use std::features;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::Coin;
    use aptos_framework::stake;
    use pictor_network::package_manager;
    use pictor_network::usdt;
    use pictor_network::pictor_network;

    const ONE_APT: u64 = 100000000;

    public fun setup(admin: &signer) {
        package_manager::initialize_for_test(admin);
        usdt::init_for_test();
        pictor_network::initialize(admin, usdt::metadata(), @0xcafe);
    }

    public fun mint_apt(apt_amount: u64): Coin<AptosCoin> {
        stake::mint_coins(apt_amount * ONE_APT)
    }

    public fun mint_usdt(to: address, usdt_amount: u64) {
        usdt::mint(deployer(), to, usdt_amount);
    }

    public inline fun deployer(): &signer {
        &account::create_signer_for_test(@0xcafe)
    }
}
