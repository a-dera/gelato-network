import { internalTask } from "@nomiclabs/buidler/config";
import { utils } from "ethers";
import sleep from "../../../../../../../helpers/async/sleep";

export default internalTask(
  "gc-mint:defaultpayload:KovanTriggerKyberRate",
  `Returns a hardcoded actionPayloadWithSelector of KovanTriggerKyberRate`
)
  .addFlag("log")
  .setAction(async ({ log }) => {
    try {
      if (network.name != "kovan") throw new Error("wrong network!");

      const contractname = "KovanTriggerKyberRate";
      // action(_user, _userProxy, _src, _srcAmt, _dest, _minConversionRate)
      const functionname = "fired";
      // Params
      const { DAI: src, KNC: dest } = await run("bre-config", {
        addressbookcategory: "erc20"
      });
      const srcamt = utils.parseUnits("10", 18);
      const [expectedRate] = await run("gt-kyber-getexpectedrate", {
        src,
        dest,
        srcamt
      });
      const refRate = utils
        .bigNumberify(expectedRate)
        .sub(utils.parseUnits("2", 16));
      const greaterElseSmaller = false;
      /*console.log(refRate.toString());
      await sleep(10000)*/

      // Params as sorted array of inputs for abi.encoding
      // action(_user, _userProxy, _src, _srcAmt, _dest)
      const inputs = [src, srcamt, dest, refRate, greaterElseSmaller];
      // Encoding
      const payloadWithSelector = await run("abi-encode-withselector", {
        contractname,
        functionname,
        inputs,
        log
      });
      return payloadWithSelector;
    } catch (err) {
      console.error(err);
      process.exit(1);
    }
  });