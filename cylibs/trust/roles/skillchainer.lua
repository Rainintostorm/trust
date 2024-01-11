local Skillchainer = setmetatable({}, {__index = Role })
Skillchainer.__index = Skillchainer

local DisposeBag = require('cylibs/events/dispose_bag')
local Event = require('cylibs/events/Luvent')
local localization_util = require('cylibs/util/localization_util')
local SkillchainAbility = require('cylibs/battle/skillchains/abilities/skillchain_ability')
local SkillchainBuilder = require('cylibs/battle/skillchains/skillchain_builder')
local SkillchainMaker = require('cylibs/battle/skillchains/skillchain_maker')
local SkillchainTracker = require('cylibs/battle/skillchains/skillchain_tracker')

state.AutoAftermathMode = M{['description'] = 'Auto Aftermath Mode', 'Off', 'Auto'}
state.AutoAftermathMode:set_description('Auto', "Okay, I'll try to keep aftermath on.")

state.AutoSkillchainMode = M{['description'] = 'Auto Skillchain Mode', 'Off', 'Auto', 'Cleave', 'Spam'}
state.AutoSkillchainMode:set_description('Auto', "Okay, I'll try to make skillchains.")
state.AutoSkillchainMode:set_description('Cleave', "Okay, I'll try to cleave monsters.")
state.AutoSkillchainMode:set_description('Spam', "Okay, I'll use the same weapon skill as soon as I get TP.")

state.SkillchainDelayMode = M{['description'] = 'Skillchain Delay Mode', 'Off', 'Maximum'}
state.SkillchainDelayMode:set_description('Maximum', "Okay, I'll wait until the end of the skillchain window to use my next weapon skill.")

state.SkillchainPartnerMode = M{['description'] = 'Skillchain Partner Mode', 'Off', 'Auto', 'Open', 'Close'}
state.SkillchainPartnerMode:set_description('Auto', "Okay, I'll let party members with the highest TP go first.")
state.SkillchainPartnerMode:set_description('Open', "Okay, I'll only open skillchains.")
state.SkillchainPartnerMode:set_description('Close', "Okay, I'll only close skillchains.")

state.SkillchainPriorityMode = M{['description'] = 'Skillchain Priority Mode', 'Off', 'Prefer', 'Strict'}
state.SkillchainPriorityMode:set_description('Prefer', "Okay, I'll prioritize using certain weapon skills.")
state.SkillchainPriorityMode:set_description('Strict', "Okay, I'll only use certain weapon skills.")

-- Event called when the player readies a weaponskill. Triggers before the weaponskill command is sent.
function Skillchainer:on_ready_weaponskill()
    return self.ready_weaponskill
end

-- Event called when a skillchain is made
function Skillchainer:on_skillchain()
    return self.skillchain
end

-- Event called when a skillchain ends
function Skillchainer:on_skillchain_ended()
    return self.skillchain_ended
end

function Skillchainer.new(action_queue, skillchain_params, skillchain_settings, job_abilities, weapon_skill_settings)
    local self = setmetatable(Role.new(action_queue), Skillchainer)

    self.action_queue = action_queue
    self.skillchain_params = skillchain_params
    self.skillchain_settings = skillchain_settings
    self.ready_weaponskill = Event.newEvent()
    self.skillchain = Event.newEvent();
    self.skillchain_ended = Event.newEvent();
    self.dispose_bag = DisposeBag.new()

    self:set_job_abilities(job_abilities)
    self:set_weapon_skill_settings(weapon_skill_settings)

    return self
end

function Skillchainer:destroy()
    Role.destroy(self)

    self:on_ready_weaponskill():removeAllActions()
    self:on_skillchain():removeAllActions()
    self:on_skillchain_ended():removeAllActions()

    self.dispose_bag:destroy()
end

function Skillchainer:on_add()
    Role.on_add(self)

    self.dispose_bag:add(state.AutoSkillchainMode:on_state_change():addAction(function(_, new_value)
        if new_value == 'Spam' then
            state.SkillchainPartnerMode:set('Off')
        end
    end), state.AutoSkillchainMode:on_state_change())

    self.skillchain_builder = SkillchainBuilder.new(L{})

    self:update_abilities()

    self.skillchain_maker = SkillchainMaker.new(self.skillchain_settings, state.AutoSkillchainMode, state.SkillchainPriorityMode, state.SkillchainPartnerMode, state.AutoAftermathMode)
    self.skillchain_maker:start_monitoring()
    self.skillchain_maker:on_perform_next_weapon_skill():addAction(function(_, weapon_skill_name)
        self:job_weapon_skill(weapon_skill_name)
    end)

    self.skillchain_tracker = SkillchainTracker.new(self:get_party())
    self.skillchain_tracker:on_skillchain():addAction(function(mob_id, step)
        local target = self:get_party():get_target(mob_id)
        if target then
            target:set_skillchain(step)
            if target:get_mob().index == self.target_index then
                self.skillchain_builder:set_step(step)
                self:show_next_skillchain_info()
                self:on_skillchain():trigger(mob_id, step)
            end
        end
    end)
    self.skillchain_tracker:on_skillchain_ended():addAction(function(mob_id)
        local target = self:get_party():get_target(mob_id)
        if target then
            target:set_skillchain(nil)
            if target:get_mob().index == self.target_index then
                self.skillchain_builder:set_step(self.skillchain_tracker:get_current_step(mob_id))
                self:show_next_skillchain_info()
                self:on_skillchain_ended():trigger(mob_id)
            end
        end
    end)

    self.dispose_bag:add(self:get_party():get_player():on_equipment_change():addAction(function(_)
        self:update_abilities()
    end), self:get_party():get_player():on_equipment_change())

    self.dispose_bag:addAny(L{ self.skillchain_maker, self.skillchain_tracker })
end

function Skillchainer:job_weapon_skill(weapon_skill_name)
    if state.AutoSkillchainMode.value == 'Off' then return end

    self:on_ready_weaponskill():trigger(weapon_skill_name, self.target_index)

    local ws = res.weapon_skills:with('en', weapon_skill_name)
    if ws then
        local actions = L{}

        for job_ability in self.job_abilities:it() do
            local job_ability_action = job_ability:to_action(windower.ffxi.get_player().index)
            if job_ability_action:can_perform() then
                actions:append(job_ability_action)
            else
                job_ability_action:destroy()
            end
        end

        actions:append(WeaponSkillAction.new(ws.name))
        actions:append(WaitAction.new(0, 0, 0, 2))

        local ws_action = SequenceAction.new(actions, 'sc_'..ws.en, true)
        ws_action.max_duration = 10
        ws_action.priority = ActionPriority.highest

        self.action_queue:push_action(ws_action, true)
    end
end

function Skillchainer:get_skillchain_settings()
    return self.skillchain_settings
end

function Skillchainer:set_skillchain_settings(skillchain_settings)
    self.skillchain_settings = skillchain_settings
    self.skillchain_maker:set_skillchain_settings(skillchain_settings)
end

function Skillchainer:show_next_skillchain_info()
    if not self:get_player():is_engaged() then
        return
    end
    local steps = self.skillchain_builder:get_next_steps()
    if steps:length() > 0 then
        local message = "I can continue the skillchain with"
        for step in steps:it() do
            message = "%s %s (%s),":format(message, localization_util.translate(step:get_ability():get_name()), step:get_skillchain())
        end
        self:get_party():add_to_chat(self:get_party():get_player(), message)
    end
end

function Skillchainer:get_skillchain_tracker()
    return self.skillchain_tracker
end

function Skillchainer:allows_duplicates()
    return false
end

function Skillchainer:get_type()
    return "skillchainer"
end

function Skillchainer:set_job_abilities(job_abilities)
    self.job_abilities = (job_abilities or L{}):filter(function(job_ability) return job_util.knows_job_ability(job_ability:get_job_ability_id()) end)
end

function Skillchainer:set_weapon_skill_settings(weapon_skill_settings)
    self.weapon_skill_settings = weapon_skill_settings

    if self:get_party() then
        self:update_abilities()
    end
end

function Skillchainer:update_abilities()
    local abilities = L{}

    local main_weapon_id = self:get_party():get_player():get_main_weapon_id()
    if main_weapon_id then
        local main_weapon = res.items[main_weapon_id]

        local combat_skills = self.weapon_skill_settings.Skills:filter(function(combat_skill_settings) return combat_skill_settings:get_skill_id() == main_weapon.skill end)
        for combat_skill in combat_skills:it() do
            abilities = abilities:extend(combat_skill:get_weapon_skills()):map(function(weapon_skill) return SkillchainAbility.new('weapon_skills', weapon_skill:get_id()) end):compact_map()
        end
    end
    self.skillchain_builder:set_abilities(abilities)
end

return Skillchainer