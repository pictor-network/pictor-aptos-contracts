#[test_only]
module pictor_network::test_helper {
    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::Coin;
    use aptos_framework::stake;
    use pictor_network::package_manager;
    use pictor_network::usdt;
    use pictor_network::pictor_network;
    use pictor_network::pictor_config;

    const ONE_APT: u64 = 100000000;
    const ADMIN_PUBKEY: vector<u8> = vector[
        32, 84, 70, 248, 137, 211, 135, 88, 23, 118, 141, 182, 184, 222, 113, 78, 128, 25,
        187, 155, 7, 173, 221, 11, 74, 148, 119, 112, 29, 92, 205, 240
    ];

    public fun setup(admin: &signer) {
        package_manager::initialize_for_test(admin);
        usdt::init_for_test();
        pictor_config::initialize(admin, usdt::metadata(), @0xcafe, ADMIN_PUBKEY);
        pictor_network::initialize(admin);
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
