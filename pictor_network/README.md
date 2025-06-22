# Running tests
aptos move compile --named-addresses deployer=0xcafe,pictor_network=0xcafe
aptos move test --named-addresses deployer=0xcafe,pictor_network=0xcafe --coverage
aptos move coverage summary --named-addresses deployer=0xcafe,pictor_network=0xcafe