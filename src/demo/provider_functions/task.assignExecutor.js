import { task } from "@nomiclabs/buidler/config";
import { defaultNetwork } from "../../../buidler.config";

export default task(
  "gelato-assign-executor",
  `Sends tx to GelatoCore.provideTaskSpecs(<TaskSpecs[]>) on [--network] (default: ${defaultNetwork})`
)
  .addFlag("log", "Logs return values to stdout")
  .setAction(async (taskArgs) => {
    try {
      const provider = getProvider();

      const executorAddress = await run("bre-config", {
        addressbook: true,
        addressbookcategory: "gelatoExecutor",
        addressbookentry: "default",
      });

      const gelatoCore = await run("instantiateContract", {
        contractname: "GelatoCore",
        signer: provider,
        write: true,
      });

      const tx = await gelatoCore.providerAssignsExecutor(executorAddress, {
        gasLimit: 1000000,
      });

      const etherscanLink = await run("get-etherscan-link", {
        txhash: tx.hash,
      });
      console.log(etherscanLink);
      await tx.wait();
      console.log(`✅ Tx mined - Executor assignment complete`);
      return `✅ Tx mined`;
    } catch (error) {
      console.error(error, "\n");
      console.log(`❌ Tx failed`);
      process.exit(1);
    }
  });
