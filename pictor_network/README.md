# Running tests
aptos move compile --named-addresses deployer=0xcafe,pictor_network=0xcafe
aptos move test --named-addresses deployer=0xcafe,pictor_network=0xcafe --coverage
aptos move coverage summary --named-addresses deployer=0xcafe,pictor_network=0xcafe


# Deployment
1. Make sure there's an Aptos profile created for the correct network (devnet/testnet/mainnet).
2. Make sure there's a separate treasury profile created as well.
3. aptos move create-resource-account-and-publish-package --profile default \
   --named-addresses deployer=default \
   --seed 2 --address-name pictor_network --included-artifacts none
   The seed can be changed to generate a different resource account address if multiple test deploys are needed.