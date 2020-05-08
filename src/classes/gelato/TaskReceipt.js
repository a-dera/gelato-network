class TaskReceipt {
  constructor({ id, userProxy, task, next, cycle }) {
    if (userProxy === undefined) throw new Error("TaskReceipt: no userProxy");
    if (task === undefined) throw new Error("TaskReceipt: no Task object");
    if (next !== undefined) next = utils.bigNumberify(next);
    if (cycle && !Array.isArray(cycle))
      throw new Error("\nTask: cycle be non-empty Array\n");

    _checkTaskBaseMembers(task);
    if (cycle !== undefined)
      for (const _task of cycle) _checkTaskBaseMembers(_task);

    this.id = id !== undefined ? id : 0;
    this.userProxy = userProxy;
    this.task = task;
    this.next = next === undefined ? utils.bigNumberify("0") : next;
    this.cycle = cycle ? cycle : [];
  }
}

async function _checkTaskBaseMembers(task) {
  if (!task.provider) throw new Error("\nTask: no provider\n");
  if (task.conditions && !Array.isArray(task.conditions))
    throw new Error("\nTask: optional conditions must be non-empty Array\n");
  if (!task.actions || !Array.isArray(task.actions) || !task.actions.length)
    throw new Error("\nTask: task.actions must be non-empty Array\n");
  if (task.autoResubmitSelf && typeof task.autoResubmitSelf !== "boolean") {
    throw new Error(
      "\nTask: task.autoResubmitSelf must be boolean if defined\n"
    );
  }
}

export default TaskReceipt;
