import hre from "hardhat";

// to run the script:
//      npx hardhat run scripts/verify/my-contract.js --network zkSyncSepoliaTestnet

async function main() {
  const contractAddress = "0xCC757016c0d0025831181c4C2Da05981bF917e4c";
  const constructorArgs = [
    "0xe95fD7f2Ee7262e2338f015D04dB352d9BcB0E6F", // _defaultAdmin
    "BuyChest",                  // _name
    "CHT",                // _symbol
    "0xe95fD7f2Ee7262e2338f015D04dB352d9BcB0E6F",     // _royaltyRecipient
    "500"            // _royaltyBps
  ];

  console.log("Verifying contract.");
  await verify(
    contractAddress,
    "contracts/BuyChestTestContract.sol:ChestBuyTest",
    constructorArgs
  );
}

async function verify(address, contract, args) {
  try {
    return await hre.run("verify:verify", {
      address: address,
      contract: contract,
      constructorArguments: args,
    });
  } catch (e) {
    console.log(address, args, e);
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
