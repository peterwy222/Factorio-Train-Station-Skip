--control.lua

script.on_event(defines.events.on_train_changed_state,
  function(event)
    if defines.train_state.on_the_path == event.train.state and event.train.schedule ~= nil and event.train.path_end_stop ~= nil and event.train.path_end_stop.name == "train-stop" then
      local nextStationIndex = event.train.schedule.current
      local originalStart = event.train.schedule.current
      while waitConditionsMet(event.train.schedule.records[nextStationIndex].wait_conditions , event.train, event.train.path_end_stop) do
        nextStationIndex = nextStationIndex + 1
        if nextStationIndex > #event.train.schedule.records then
          nextStationIndex = 1
        end
        event.train.go_to_station(nextStationIndex)
        if originalStart == nextStationIndex then
          break
        end
      end
    end
  end
)

function waitConditionsMet(waitConditions, train, trainStop)
  -- This will store the latest computed result
  local result = false
  if waitConditions == nil then
    return false
  end
  for _, waitCondition in ipairs(waitConditions) do
    if waitCondition.compare_type == "or" then
      -- True || anything is still true, return here
      if result == true then
        return true
      end
      -- False || anything is just itself
      result = waitConditionMet(waitCondition, train, trainStop)
    else
      result = result and waitConditionMet(waitCondition, train, trainStop)
    end
  end
  return result
end

function waitConditionMet(waitCondition, train, trainStop)
  local circuitCondition = waitCondition.condition
  local waitConditionTypeMap = {
    time = false,
    inactivity = false,
    full = function()
      for _, carriage in ipairs(train.carriages) do
        if carriage.name ~= "locomotive" then
          if carriage.fluidbox ~= nil and #carriage.fluidbox > 0 then
            if carriage.fluidbox[1] == nil or carriage.fluidbox[1].amount < carriage.fluidbox.get_capacity(1) then
              return false
            end
          elseif carriage.get_inventory(defines.inventory.artillery_wagon_ammo) ~= nil then
            if carriage.get_inventory(defines.inventory.artillery_wagon_ammo).can_insert({name="artillery-shell"}) then
              return false
            end
          else
            if not carriage.get_inventory(defines.inventory.cargo_wagon).is_full() then
              return false
            end
          end
        end
      end
      return true
    end,
    empty = function()
      for _, carriage in ipairs(train.carriages) do
        if carriage.name ~= "locomotive" then
          if carriage.fluidbox ~= nil and #carriage.fluidbox > 0 then
            if carriage.fluidbox[1] ~= nil and carriage.fluidbox[1].amount >= 0 then
              return false
            end
          elseif carriage.get_inventory(defines.inventory.artillery_wagon_ammo) ~= nil then
            if not carriage.get_inventory(defines.inventory.artillery_wagon_ammo).is_empty() then
              return false
            end
          else
            if not carriage.get_inventory(defines.inventory.cargo_wagon).is_empty() then
              return false
            end
          end
        end
      end
      return true
    end,
    item_count = function()
      local firstSignal = circuitCondition.first_signal ~= nil and train.get_item_count(circuitCondition.first_signal.name) or nil
      local secondSignal = circuitCondition.second_signal ~= nil and train.get_item_count(circuitCondition.second_signal.name) or circuitCondition.constant
      return circuitConditionMet(circuitCondition.comparator, firstSignal, secondSignal)
    end,
    circuit = function()
      if trainStop.get_control_behavior().send_to_train then
        return controlBehaviorCircuitConditionMet(trainStop.get_control_behavior(), waitCondition.condition)
      end
      return false
    end,
    robots_inactive = false,
    fluid_count = function()
      local firstSignal = circuitCondition.first_signal ~= nil and train.get_fluid_count(circuitCondition.first_signal.name) or nil
      local secondSignal = circuitCondition.second_signal ~= nil and train.get_fluid_count(circuitCondition.second_signal.name) or circuitCondition.constant
      return circuitConditionMet(circuitCondition.comparator, firstSignal, secondSignal)
    end,
    passenger_present = function()
      return #train.passengers > 0
    end,
    passenger_not_present = function()
      return #train.passengers == 0
    end
  }
  if type(waitConditionTypeMap[waitCondition.type]) == "function" then
    return waitConditionTypeMap[waitCondition.type]()
  elseif waitConditionTypeMap[waitCondition.type] == nil then
    return false
  else
    return waitConditionTypeMap[waitCondition.type]
  end
end

function controlBehaviorCircuitConditionMet(controlBehavior, condition)
  local redFirstSignal = controlBehavior.get_circuit_network(defines.wire_type.red).get_signal(condition.first_signal)
  local greenFirstSignal = controlBehavior.get_circuit_network(defines.wire_type.green).get_signal(condition.first_signal)
  local redSecondSignal = condition.constant
  local greenSecondSignal = condition.constant
  if condition.second_signal ~= nil then
    redSecondSignal = controlBehavior.get_circuit_network(defines.wire_type.red).get_signal(condition.second_signal)
    greenSecondSignal = controlBehavior.get_circuit_network(defines.wire_type.green).get_signal(condition.second_signal)
  end
  return circuitConditionMet(condition.comparator, redFirstSignal, redSecondSignal) or circuitConditionMet(condition.comparator, greenFirstSignal, greenSecondSignal)
end

function circuitConditionMet(comparator, firstSignal, secondSignal)
  if firstSignal == nil or secondSignal == nil then
    return false
  end
  local comparatorMap = {
    ["="] = function ()
      return firstSignal == secondSignal
    end,
    [">"] = function ()
      return firstSignal > secondSignal
    end,
    ["<"] = function ()
      return firstSignal < secondSignal
    end,
    ["≥"] = function ()
      return firstSignal >= secondSignal
    end,
    ["≤"] = function ()
      return firstSignal <= secondSignal
    end,
    ["≠"] = function ()
      return firstSignal ~= secondSignal
    end
  }
  return comparatorMap[comparator]()
end
