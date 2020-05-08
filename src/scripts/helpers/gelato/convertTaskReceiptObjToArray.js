/*
struct Provider {
    address addr;  //  if msg.sender == provider => self-Provider
    IGelatoProviderModule module;  //  can be IGelatoProviderModule(0) for self-Providers
}

struct Condition {
    IGelatoCondition inst;  // can be AddressZero for self-conditional Actions
    bytes data;  // can be bytes32(0) for self-conditional Actions
}

enum Operation { Call, Delegatecall }

struct Action {
    address addr;
    bytes data;
    Operation operation;
    uint256 value;
    bool termsOkCheck;
}


struct TaskReceipt {
    uint256 id;
    address userProxy;
    Task task;
}
 */

function convertTaskReceiptObjToArray(taskReceiptObj) {
  const provider = _convertToProviderArray(taskReceiptObj.task.base.provider);

  const conditions = _convertToArrayOfConditionArrays(
    taskReceiptObj.task.base.conditions
  );

  const actions = _convertToArrayOfActionArrays(
    taskReceiptObj.task.base.actions
  );

  const base = [
    provider,
    conditions,
    actions,
    taskReceiptObj.task.base.expiryDate,
    taskReceiptObj.task.base.autoResubmitSelf,
  ];

  const cycle = _convertToArrayOfTaskBaseArrays(taskReceiptObj.task.cycle);

  const task = [base, taskReceiptObj.task.next, cycle];

  const taskReceiptArray = [taskReceiptObj.id, taskReceiptObj.userProxy, task];

  return taskReceiptArray;
}

function _convertToProviderArray(providerObj) {
  const providerArray = [providerObj.addr, providerObj.module];
  return providerArray;
}

function _convertToArrayOfConditionArrays(arrayOfConditionObjs) {
  const conditions = [];
  for (const conditionObj of arrayOfConditionObjs) {
    const conditionArray = [conditionObj.inst, conditionObj.data];
    conditions.push(conditionArray);
  }
  return conditions;
}

function _convertToArrayOfActionArrays(arrayOfActionObjs) {
  const actions = [];
  for (const actionObj of arrayOfActionObjs) {
    const actionArray = [
      actionObj.addr,
      actionObj.data,
      actionObj.operation,
      actionObj.value,
      actionObj.termsOkCheck,
    ];
    actions.push(actionArray);
  }
  return actions;
}

function _convertToArrayOfTaskBaseArrays(arrayOfTaskBaseObjs) {
  const taskBases = [];
  for (const taskBaseObj of arrayOfTaskBaseObjs) {
    const taskBaseArray = [
      _convertToProviderArray(taskBaseObj.provider),
      _convertToArrayOfConditionArrays(taskBaseObj.conditions),
      _convertToArrayOfActionArrays(taskBaseObj.actions),
      taskBaseObj.expiryDate,
      taskBaseObj.autoResubmitSelf,
    ];
    taskBases.push(taskBaseArray);
  }
  return taskBases;
}

export default convertTaskReceiptObjToArray;
