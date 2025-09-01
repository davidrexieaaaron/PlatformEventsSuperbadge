trigger BatchErrorEventTrigger1 on BatchApexErrorEvent (after insert) {
    BatchErrorEventHelper.handleBatchErrorEvents(trigger.new);
}