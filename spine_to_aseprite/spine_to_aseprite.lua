-- Spine to Aseprite Animation Converter
-- Converts Spine JSON animation data to Aseprite using RotSprite algorithm

-- Simple JSON parser for Lua
local function parseJSON(str)
    -- Remove whitespace
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    
    local function parseValue(s, pos)
        pos = pos or 1
        local char = s:sub(pos, pos)
        
        -- Skip whitespace
        while char:match("%s") and pos <= #s do
            pos = pos + 1
            char = s:sub(pos, pos)
        end
        
        if char == '"' then
            -- Parse string
            local endPos = pos + 1
            while endPos <= #s do
                if s:sub(endPos, endPos) == '"' and s:sub(endPos-1, endPos-1) ~= '\\' then
                    break
                end
                endPos = endPos + 1
            end
            return s:sub(pos + 1, endPos - 1), endPos + 1
        elseif char == '{' then
            -- Parse object
            local obj = {}
            pos = pos + 1
            
            -- Skip whitespace
            while s:sub(pos, pos):match("%s") and pos <= #s do
                pos = pos + 1
            end
            
            if s:sub(pos, pos) == '}' then
                return obj, pos + 1
            end
            
            while pos <= #s do
                -- Parse key
                local key, newPos = parseValue(s, pos)
                pos = newPos
                
                -- Skip whitespace and colon
                while (s:sub(pos, pos):match("%s") or s:sub(pos, pos) == ':') and pos <= #s do
                    pos = pos + 1
                end
                
                -- Parse value
                local value
                value, pos = parseValue(s, pos)
                if key then
                    obj[key] = value
                end
                
                -- Skip whitespace
                while s:sub(pos, pos):match("%s") and pos <= #s do
                    pos = pos + 1
                end
                
                if s:sub(pos, pos) == '}' then
                    return obj, pos + 1
                elseif s:sub(pos, pos) == ',' then
                    pos = pos + 1
                end
            end
        elseif char == '[' then
            -- Parse array
            local arr = {}
            pos = pos + 1
            local index = 1
            
            -- Skip whitespace
            while s:sub(pos, pos):match("%s") and pos <= #s do
                pos = pos + 1
            end
            
            if s:sub(pos, pos) == ']' then
                return arr, pos + 1
            end
            
            while pos <= #s do
                local value
                value, pos = parseValue(s, pos)
                arr[index] = value
                index = index + 1
                
                -- Skip whitespace
                while s:sub(pos, pos):match("%s") and pos <= #s do
                    pos = pos + 1
                end
                
                if s:sub(pos, pos) == ']' then
                    return arr, pos + 1
                elseif s:sub(pos, pos) == ',' then
                    pos = pos + 1
                end
            end
        else
            -- Parse number, boolean, or null
            local endPos = pos
            while endPos <= #s and not s:sub(endPos, endPos):match("[,}%]%s]") do
                endPos = endPos + 1
            end
            
            local valueStr = s:sub(pos, endPos - 1)
            if valueStr == "true" then
                return true, endPos
            elseif valueStr == "false" then
                return false, endPos
            elseif valueStr == "null" then
                return nil, endPos
            else
                local num = tonumber(valueStr)
                return num or valueStr, endPos
            end
        end
        
        return nil, pos
    end
    
    local result, _ = parseValue(str)
    return result
end

-- Build bone hierarchy from parsed JSON data
local function buildBoneHierarchy(data)
    if not data.bones then
        return nil
    end
    
    local bones = {}
    local bonesByName = {}
    
    -- 1.Create all bones
    for i, boneData in ipairs(data.bones) do
        local bone = {
            name = boneData.name,
            parent = nil,
            children = {},
            
            -- Setup pose (from JSON)
            setupX = boneData.x or 0,
            setupY = boneData.y or 0,
            setupRotation = boneData.rotation or 0,
            setupScaleX = boneData.scaleX or 1,
            setupScaleY = boneData.scaleY or 1,
            length = boneData.length or 0,
            
            -- Current transform (will be calculated during animation)
            x = boneData.x or 0,
            y = boneData.y or 0,
            rotation = boneData.rotation or 0,
            scaleX = boneData.scaleX or 1,
            scaleY = boneData.scaleY or 1,
            
            -- World transform matrices (will be calculated)
            worldMatrix = nil,
            localMatrix = nil
        }
        
        bones[i] = bone
        bonesByName[bone.name] = bone
    end
    
    -- 2.Establish parent-child relationships
    for i, boneData in ipairs(data.bones) do
        local bone = bones[i]
        if boneData.parent then
            local parentBone = bonesByName[boneData.parent]
            if parentBone then
                bone.parent = parentBone
                table.insert(parentBone.children, bone)
            end
        end
    end
    
    -- Find root bones
    local rootBones = {}
    for _, bone in ipairs(bones) do
        if not bone.parent then
            table.insert(rootBones, bone)
        end
    end
    
    return {
        bones = bones,
        bonesByName = bonesByName,
        rootBones = rootBones
    }
end

-- Calculate bone world transforms
local function calculateBoneTransforms(boneSystem)
    -- Helper function to create 2D transform matrix (corrected for Spine coordinate system)
    local function createMatrix(x, y, rotation, scaleX, scaleY)
        local cos_r = math.cos(math.rad(rotation))
        local sin_r = math.sin(math.rad(rotation))
        
        -- Debug check for invalid input values (removed for performance)
        if scaleX == 0 or scaleY == 0 then
            scaleX = scaleX == 0 and 0.001 or scaleX
            scaleY = scaleY == 0 and 0.001 or scaleY
        end
        
        return {
            a = cos_r * scaleX,   -- m00
            b = -sin_r * scaleX,  -- m01 (corrected sign)
            c = sin_r * scaleY,   -- m10
            d = cos_r * scaleY,   -- m11
            tx = x,               -- translation x
            ty = y                -- translation y
        }
    end
    
    -- Helper function to multiply matrices (standard matrix multiplication)
    local function multiplyMatrix(parent, local_m)
        return {
            a = parent.a * local_m.a + parent.b * local_m.c,
            b = parent.a * local_m.b + parent.b * local_m.d,
            c = parent.c * local_m.a + parent.d * local_m.c,
            d = parent.c * local_m.b + parent.d * local_m.d,
            tx = parent.a * local_m.tx + parent.b * local_m.ty + parent.tx,
            ty = parent.c * local_m.tx + parent.d * local_m.ty + parent.ty
        }
    end
    
    -- Recursive function to calculate transforms
    local function calculateBoneTransform(bone, parentWorldMatrix)
        -- Debug check for bone data before creating matrix (removed for performance)
        
        -- Create local transform matrix
        bone.localMatrix = createMatrix(bone.x, bone.y, bone.rotation, bone.scaleX, bone.scaleY)
        
        -- Calculate world transform
        if parentWorldMatrix then
            bone.worldMatrix = multiplyMatrix(parentWorldMatrix, bone.localMatrix)
        else
            bone.worldMatrix = bone.localMatrix
        end
        
        -- Process children
        for _, child in ipairs(bone.children) do
            calculateBoneTransform(child, bone.worldMatrix)
        end
    end
    
    -- Calculate transforms for all root bones
    for _, rootBone in ipairs(boneSystem.rootBones) do
        calculateBoneTransform(rootBone, nil)
    end
end    -- Process animation data with Bezier interpolation
local function processAnimationData(data, boneSystem)
    if not data.animations then
        return nil
    end

    local processedAnimations = {}
    
    -- Helper function for cubic Bezier interpolation
    local function cubicBezier(t, p0, p1, p2, p3)
        local u = 1 - t
        return u*u*u*p0 + 3*u*u*t*p1 + 3*u*t*t*p2 + t*t*t*p3
    end
    
    -- Helper function to find keyframes and interpolate attachment visibility
    local function interpolateAttachmentVisibility(keyframes, time, defaultValue)
        if not keyframes or #keyframes == 0 then
            return defaultValue
        end
        
        -- Find the keyframe at or before the current time
        local activeKeyframe = nil
        for i, frame in ipairs(keyframes) do
            local frameTime = frame.time or 0
            if frameTime <= time then
                activeKeyframe = frame
            else
                break
            end
        end
        
        if activeKeyframe then
            -- If name field exists, attachment is visible; if missing, it's hidden
            return activeKeyframe.name ~= nil, activeKeyframe.name
        end
        
        return defaultValue, nil
    end
    
    -- Helper function to find keyframes and interpolate values
    local function interpolateValue(keyframes, time, defaultValue, valueKey)
        if not keyframes or #keyframes == 0 then
            return defaultValue
        end

        valueKey = valueKey or "value"  -- default to "value" for rotation, "x" or "y" for translation/scale

        -- Find surrounding keyframes
        local prevFrame, nextFrame = nil, nil
        for i, frame in ipairs(keyframes) do
            local frameTime = frame.time or 0
            if frameTime <= time then
                prevFrame = frame
            end
            if frameTime >= time and not nextFrame then
                nextFrame = frame
                break
            end
        end

        -- If exact match or only one keyframe
        if prevFrame and (prevFrame.time or 0) == time then
            return prevFrame[valueKey] or defaultValue
        end

        if not prevFrame then
            return nextFrame and (nextFrame[valueKey] or defaultValue) or defaultValue
        end

        if not nextFrame then
            return prevFrame[valueKey] or defaultValue
        end

        -- Bezier interpolation
        local t0 = prevFrame.time or 0
        local t1 = nextFrame.time or 0
        local v0 = prevFrame[valueKey] or defaultValue
        local v1 = nextFrame[valueKey] or defaultValue

        if t1 == t0 then
            return v0
        end

        local normalizedTime = (time - t0) / (t1 - t0)

        -- Get context information
        local contextInfo = ""
        if prevFrame.boneName or prevFrame.slotName then
            contextInfo = contextInfo .. string.format("  Target: %s\n", prevFrame.boneName or prevFrame.slotName)
        end
        if prevFrame.transformType then
            contextInfo = contextInfo .. string.format("  Transform: %s\n", prevFrame.transformType)
        end
        contextInfo = contextInfo .. string.format("  Frame time: %.6f\n", time)

        -- Check interpolation mode
        if prevFrame.curve == "stepped" then
            -- Stepped interpolation: hold the previous value until the next keyframe
            return v0
        elseif prevFrame.curve and type(prevFrame.curve) == "table" and #prevFrame.curve >= 4 then
            -- Support 4-value and 8-value Bezier curves
            local cx1, cy1, cx2, cy2
            if #prevFrame.curve >= 8 then
                -- 8-value format for position: first 4 for X-axis (x1,y1,x2,y2), next 4 for Y-axis (x1,y1,x2,y2)
                if valueKey == "x" then
                    cx1, cy1, cx2, cy2 = prevFrame.curve[1], prevFrame.curve[2], prevFrame.curve[3], prevFrame.curve[4]
                elseif valueKey == "y" then
                    cx1, cy1, cx2, cy2 = prevFrame.curve[5], prevFrame.curve[6], prevFrame.curve[7], prevFrame.curve[8]
                else
                    -- rotate/scale/others, use only first 4 values
                    cx1, cy1, cx2, cy2 = prevFrame.curve[1], prevFrame.curve[2], prevFrame.curve[3], prevFrame.curve[4]
                end
            else
                -- 4-value format
                cx1, cy1, cx2, cy2 = prevFrame.curve[1], prevFrame.curve[2], prevFrame.curve[3], prevFrame.curve[4]
            end
            local errorReason = nil
            local normalizedCx1, normalizedCx2, normalizedCy1, normalizedCy2
            if t1 == t0 then
                errorReason = string.format("t1 == t0 (%.6f == %.6f), division by zero", t1, t0)
            else
                normalizedCx1 = (cx1 - t0) / (t1 - t0)
                normalizedCx2 = (cx2 - t0) / (t1 - t0)
                if normalizedCx1 ~= normalizedCx1 or normalizedCx2 ~= normalizedCx2 then
                    errorReason = string.format("normalizedCx1 or normalizedCx2 is NaN; cx1=%.6f, cx2=%.6f, t0=%.6f, t1=%.6f", cx1, cx2, t0, t1)
                end
            end
            if v1 == v0 then
                errorReason = string.format("v1 == v0 (%.6f == %.6f), division by zero", v1, v0)
            else
                normalizedCy1 = (cy1 - v0) / (v1 - v0)
                normalizedCy2 = (cy2 - v0) / (v1 - v0)
                if normalizedCy1 ~= normalizedCy1 or normalizedCy2 ~= normalizedCy2 then
                    errorReason = string.format("normalizedCy1 or normalizedCy2 is NaN; cy1=%.6f, cy2=%.6f, v0=%.6f, v1=%.6f", cy1, cy2, v0, v1)
                end
            end

            -- Find the correct t value for our time using the x-curve
            local function solveBezierX(targetX, epsilon)
                epsilon = epsilon or 1e-6
                local t = targetX  -- initial guess
                for i = 1, 10 do  -- Newton-Raphson iterations
                    local x = cubicBezier(t, 0, normalizedCx1, normalizedCx2, 1)
                    local dx = 3 * (1-t)^2 * normalizedCx1 + 6 * (1-t) * t * (normalizedCx2 - normalizedCx1) + 3 * t^2 * (1 - normalizedCx2)
                    if math.abs(x - targetX) < epsilon then break end
                    if math.abs(dx) < epsilon then break end
                    t = t - (x - targetX) / dx
                    t = math.max(0, math.min(1, t))  -- clamp to [0,1]
                end
                return t
            end

            local bezierT = solveBezierX(normalizedTime)
            local normalizedY = nil
            local result = nil
            if not errorReason then
                normalizedY = cubicBezier(bezierT, 0, normalizedCy1, normalizedCy2, 1)
                result = v0 + normalizedY * (v1 - v0)
            end

            if errorReason then
                return v0 + (v1 - v0) * normalizedTime
            end

            return result
        else
            -- Linear interpolation fallback
            return v0 + (v1 - v0) * normalizedTime
        end
        
    end
    
    for animName, animation in pairs(data.animations) do
        local processedAnim = {
            name = animName,
            frames = {}
        }
        
        -- Generate frames at 0.1 second intervals
        local animationLength = 0
        
        -- Find animation length
        if animation.bones then
            for boneName, boneAnim in pairs(animation.bones) do
                if boneAnim.rotate then
                    for _, keyframe in ipairs(boneAnim.rotate) do
                        animationLength = math.max(animationLength, keyframe.time or 0)
                    end
                end
                if boneAnim.translate then
                    for _, keyframe in ipairs(boneAnim.translate) do
                        animationLength = math.max(animationLength, keyframe.time or 0)
                    end
                end
                if boneAnim.scale then
                    for _, keyframe in ipairs(boneAnim.scale) do
                        animationLength = math.max(animationLength, keyframe.time or 0)
                    end
                end
            end
        end
        
        -- Find animation length from slot animations (attachment visibility)
        if animation.slots then
            for slotName, slotAnim in pairs(animation.slots) do
                if slotAnim.attachment then
                    for _, keyframe in ipairs(slotAnim.attachment) do
                        animationLength = math.max(animationLength, keyframe.time or 0)
                    end
                end
            end
        end
        
        -- Create frames
        local frameInterval = 0.1
        if _G and _G.__aseprite_spine2aseprite_fps then
            frameInterval = 1 / _G.__aseprite_spine2aseprite_fps
        end
        local frameCount = math.max(1, math.floor(animationLength / frameInterval + 0.5))
        for frame = 0, frameCount - 1 do
            local time = frame * frameInterval
            
            local frameData = {
                time = time,
                bones = {},
                attachments = {}
            }
            
            -- Process bone animations with interpolation
            for _, bone in ipairs(boneSystem.bones) do
                local boneName = bone.name
                local boneAnim = animation.bones and animation.bones[boneName]

                local localRotation = bone.setupRotation
                local localX = bone.setupX
                local localY = bone.setupY
                local localScaleX = bone.setupScaleX
                local localScaleY = bone.setupScaleY

                -- Add context to keyframes
                local function addContextToKeyframes(keyframes, transformType)
                    if keyframes then
                        for _, kf in ipairs(keyframes) do
                            kf.boneName = boneName
                            kf.transformType = transformType
                        end
                    end
                end

                if boneAnim then
                    -- Interpolate rotation
                    if boneAnim.rotate then
                        addContextToKeyframes(boneAnim.rotate, "rotate")
                        local rotValue = interpolateValue(boneAnim.rotate, time, 0, "value")
                        localRotation = bone.setupRotation + rotValue
                    end

                    -- Interpolate translation
                    if boneAnim.translate then
                        addContextToKeyframes(boneAnim.translate, "translate")
                        -- Determine which axis (x/y) has movement
                        local function getDelta(keyframes, key)
                            if not keyframes or #keyframes == 0 then return 0 end
                            local minV, maxV = nil, nil
                            for _, kf in ipairs(keyframes) do
                                local v = kf[key] or 0
                                if not minV or v < minV then minV = v end
                                if not maxV or v > maxV then maxV = v end
                            end
                            return math.abs((maxV or 0) - (minV or 0))
                        end

                        local deltaX = getDelta(boneAnim.translate, "x")
                        local deltaY = getDelta(boneAnim.translate, "y")

                        local useBezierX = deltaX > 1e-4 and deltaY < 1e-4
                        local useBezierY = deltaY > 1e-4 and deltaX < 1e-4

                        local transX, transY
                        if useBezierX then
                            -- Only x moves: use Bezier for x, linear for y
                            transX = interpolateValue(boneAnim.translate, time, 0, "x")
                            -- Force linear interpolation for y
                            local function linearInterpolate(keyframes, time, defaultValue, valueKey)
                                if not keyframes or #keyframes == 0 then return defaultValue end
                                local prevFrame, nextFrame = nil, nil
                                for i, frame in ipairs(keyframes) do
                                    local frameTime = frame.time or 0
                                    if frameTime <= time then prevFrame = frame end
                                    if frameTime >= time and not nextFrame then nextFrame = frame break end
                                end
                                if prevFrame and (prevFrame.time or 0) == time then return prevFrame[valueKey] or defaultValue end
                                if not prevFrame then return nextFrame and (nextFrame[valueKey] or defaultValue) or defaultValue end
                                if not nextFrame then return prevFrame[valueKey] or defaultValue end
                                local t0 = prevFrame.time or 0
                                local t1 = nextFrame.time or 0
                                local v0 = prevFrame[valueKey] or defaultValue
                                local v1 = nextFrame[valueKey] or defaultValue
                                if t1 == t0 then return v0 end
                                local normalizedTime = (time - t0) / (t1 - t0)
                                return v0 + (v1 - v0) * normalizedTime
                            end
                            transY = linearInterpolate(boneAnim.translate, time, 0, "y")
                        elseif useBezierY then
                            -- Only y moves: use Bezier for y, linear for x
                            transY = interpolateValue(boneAnim.translate, time, 0, "y")
                            local function linearInterpolate(keyframes, time, defaultValue, valueKey)
                                if not keyframes or #keyframes == 0 then return defaultValue end
                                local prevFrame, nextFrame = nil, nil
                                for i, frame in ipairs(keyframes) do
                                    local frameTime = frame.time or 0
                                    if frameTime <= time then prevFrame = frame end
                                    if frameTime >= time and not nextFrame then nextFrame = frame break end
                                end
                                if prevFrame and (prevFrame.time or 0) == time then return prevFrame[valueKey] or defaultValue end
                                if not prevFrame then return nextFrame and (nextFrame[valueKey] or defaultValue) or defaultValue end
                                if not nextFrame then return prevFrame[valueKey] or defaultValue end
                                local t0 = prevFrame.time or 0
                                local t1 = nextFrame.time or 0
                                local v0 = prevFrame[valueKey] or defaultValue
                                local v1 = nextFrame[valueKey] or defaultValue
                                if t1 == t0 then return v0 end
                                local normalizedTime = (time - t0) / (t1 - t0)
                                return v0 + (v1 - v0) * normalizedTime
                            end
                            transX = linearInterpolate(boneAnim.translate, time, 0, "x")
                        else
                            -- Both axes move or neither moves: use normal Bezier interpolation
                            transX = interpolateValue(boneAnim.translate, time, 0, "x")
                            transY = interpolateValue(boneAnim.translate, time, 0, "y")
                        end
                        localX = bone.setupX + transX
                        localY = bone.setupY + transY
                    end

                    -- Interpolate scale
                    if boneAnim.scale then
                        addContextToKeyframes(boneAnim.scale, "scale")
                        local scaleX = interpolateValue(boneAnim.scale, time, 1, "x")
                        local scaleY = interpolateValue(boneAnim.scale, time, 1, "y")
                        localScaleX = bone.setupScaleX * scaleX
                        localScaleY = bone.setupScaleY * scaleY
                    end
                end

                -- Debug check for NaN in calculated values (removed for performance)

                frameData.bones[boneName] = {
                    x = localX,
                    y = localY,
                    rotation = localRotation,
                    scaleX = localScaleX,
                    scaleY = localScaleY
                }
            end
            
            -- Process attachments (process all attachments regardless of name matching)
            if data.skins and data.skins[1] and data.skins[1].attachments then
                for slotName, attachments in pairs(data.skins[1].attachments) do
                    for attachName, attachment in pairs(attachments) do
                        -- Get the bone of the attachment
                        local attachmentBone = nil
                        if data.slots then
                            for _, slot in ipairs(data.slots) do
                                if slot.name == slotName then
                                    attachmentBone = boneSystem.bonesByName[slot.bone]
                                    break
                                end
                            end
                        end

                        -- Only process when the bone of the attachment is found and the bone name does not start with "skip"
                        if attachmentBone and not string.find(string.lower(attachmentBone.name), "^skip") then
                            -- Check the default attachment in the slot's setup pose
                            local setupDefaultAttachment = nil
                            if data.slots then
                                for _, slot in ipairs(data.slots) do
                                    if slot.name == slotName then
                                        setupDefaultAttachment = slot.attachment
                                        break
                                    end
                                end
                            end
                            
                            -- Determine default visibility: only visible by default when the current attachment is the slot's default attachment
                            local defaultVisible = (setupDefaultAttachment == attachName)
                            
                            -- Check slot animation for attachment visibility
                            local isVisible = defaultVisible  -- Use the setup pose state as default values
                            local currentAttachmentName = attachName

                            -- Add context to keyframes
                            local function addContextToSlotKeyframes(keyframes)
                                if keyframes then
                                    for _, kf in ipairs(keyframes) do
                                        kf.slotName = slotName
                                        kf.transformType = "attachment"
                                    end
                                end
                            end

                            if animation.slots and animation.slots[slotName] and animation.slots[slotName].attachment then
                                addContextToSlotKeyframes(animation.slots[slotName].attachment)
                                local visible, activeName = interpolateAttachmentVisibility(
                                    animation.slots[slotName].attachment,
                                    time,
                                    defaultVisible  -- Use the setup pose state as default values
                                )
                                isVisible = visible
                                if activeName then
                                    currentAttachmentName = activeName
                                end
                                -- If the current attachment name doesn't match the active one, hide it
                                if activeName and activeName ~= attachName then
                                    isVisible = false
                                end
                            else
                                -- When there are no animation keyframes, check if other attachments are active at this time point
                                -- If the current attachment is not the default one and no animation makes it active, it should remain hidden
                                if not defaultVisible then
                                    isVisible = false
                                end
                            end

                            frameData.attachments[attachName] = {
                                x = attachment.x or 0,
                                y = attachment.y or 0,
                                rotation = attachment.rotation or 0,
                                scaleX = attachment.scaleX or 1,
                                scaleY = attachment.scaleY or 1,
                                bone = attachmentBone.name,
                                visible = isVisible,
                                activeName = currentAttachmentName
                            }
                        end
                    end
                end
            end
            
            table.insert(processedAnim.frames, frameData)
            
            -- Convert to world coordinates
            -- First, update bone transforms with interpolated values
            for _, bone in ipairs(boneSystem.bones) do
                local boneName = bone.name
                local boneFrameData = frameData.bones[boneName]
                if boneFrameData then
                    -- Debug check for NaN in frame data before updating bone (removed for performance)
                    
                    bone.x = boneFrameData.x
                    bone.y = boneFrameData.y
                    bone.rotation = boneFrameData.rotation
                    bone.scaleX = boneFrameData.scaleX
                    bone.scaleY = boneFrameData.scaleY
                end
            end
            
            -- Calculate world transforms for this frame
            calculateBoneTransforms(boneSystem)
            
            -- Convert bone local coordinates to world coordinates
            for boneName, boneData in pairs(frameData.bones) do
                local bone = boneSystem.bonesByName[boneName]
                if bone and bone.worldMatrix then
                    local worldMatrix = bone.worldMatrix
                    -- Extract world position from transform matrix
                    boneData.worldX = worldMatrix.tx
                    boneData.worldY = worldMatrix.ty
                    
                    -- Extract world rotation (approximation from matrix)
                    boneData.worldRotation = math.deg(math.atan(worldMatrix.c, worldMatrix.a))
                    
                    -- Extract world scale (approximation from matrix)
                    boneData.worldScaleX = math.sqrt(worldMatrix.a * worldMatrix.a + worldMatrix.c * worldMatrix.c)
                    boneData.worldScaleY = math.sqrt(worldMatrix.b * worldMatrix.b + worldMatrix.d * worldMatrix.d)
                    
                    -- Debug check for NaN in bone world coordinates (removed for performance)
                end
            end
            
            -- Convert attachment local coordinates to world coordinates
            for attachName, attachData in pairs(frameData.attachments) do
                local attachmentBone = boneSystem.bonesByName[attachData.bone]
                if attachmentBone and attachmentBone.worldMatrix then
                    local boneWorldMatrix = attachmentBone.worldMatrix
                    
                    -- Create attachment local transform matrix
                    local cos_r = math.cos(math.rad(attachData.rotation))
                    local sin_r = math.sin(math.rad(attachData.rotation))
                    
                    local attachLocalMatrix = {
                        a = cos_r * attachData.scaleX,
                        b = -sin_r * attachData.scaleX,
                        c = sin_r * attachData.scaleY,
                        d = cos_r * attachData.scaleY,
                        tx = attachData.x,
                        ty = attachData.y
                    }
                    
                    -- Multiply bone world matrix with attachment local matrix
                    local attachWorldMatrix = {
                        a = boneWorldMatrix.a * attachLocalMatrix.a + boneWorldMatrix.b * attachLocalMatrix.c,
                        b = boneWorldMatrix.a * attachLocalMatrix.b + boneWorldMatrix.b * attachLocalMatrix.d,
                        c = boneWorldMatrix.c * attachLocalMatrix.a + boneWorldMatrix.d * attachLocalMatrix.c,
                        d = boneWorldMatrix.c * attachLocalMatrix.b + boneWorldMatrix.d * attachLocalMatrix.d,
                        tx = boneWorldMatrix.a * attachLocalMatrix.tx + boneWorldMatrix.b * attachLocalMatrix.ty + boneWorldMatrix.tx,
                        ty = boneWorldMatrix.c * attachLocalMatrix.tx + boneWorldMatrix.d * attachLocalMatrix.ty + boneWorldMatrix.ty
                    }
                    
                    -- Extract world coordinates
                    attachData.worldX = attachWorldMatrix.tx
                    attachData.worldY = attachWorldMatrix.ty
                    attachData.worldRotation = math.deg(math.atan(attachWorldMatrix.c, attachWorldMatrix.a))
                    attachData.worldScaleX = math.sqrt(attachWorldMatrix.a * attachWorldMatrix.a + attachWorldMatrix.c * attachWorldMatrix.c)
                    attachData.worldScaleY = math.sqrt(attachWorldMatrix.b * attachWorldMatrix.b + attachWorldMatrix.d * attachWorldMatrix.d)
                    
                    -- Debug check for NaN in world coordinate calculation (removed for performance)
                end
            end
        end
        
        processedAnimations[animName] = processedAnim
    end
    
    return processedAnimations
end

-- Coordinate system conversion functions
-- Spine: Y-axis points up (+Y), counterclockwise rotation is positive
-- Aseprite: Y-axis points down (+Y), clockwise rotation is positive
local function spineToAsepriteCoords(spineX, spineY, rootX, rootY)
    -- Convert from Spine world coordinates to Aseprite pixel coordinates
    -- Flip Y axis and add root offset
    local asepriteX = rootX + spineX
    local asepriteY = rootY - spineY  -- Flip Y axis
    return asepriteX, asepriteY
end

local function spineToAsepriteRotation(spineRotation)
    -- Convert from Spine rotation (counterclockwise positive) 
    -- to Aseprite rotation (clockwise positive)
    return -spineRotation
end

-- Apply coordinate system conversion to animation data
local function convertAnimationToAsepriteCoords(animationData, rootPosition)
    if not rootPosition then
        return animationData
    end
    
    for animName, animation in pairs(animationData) do
        for frameIndex, frame in ipairs(animation.frames) do
            -- Convert bone world coordinates
            for boneName, boneData in pairs(frame.bones) do
                if boneData.worldX and boneData.worldY then
                    local asepriteX, asepriteY = spineToAsepriteCoords(
                        boneData.worldX, boneData.worldY, 
                        rootPosition.x, rootPosition.y
                    )
                    boneData.asepriteX = asepriteX
                    boneData.asepriteY = asepriteY
                    boneData.asepriteRotation = spineToAsepriteRotation(boneData.worldRotation or 0)
                end
            end
            
            -- Convert attachment world coordinates
            for attachName, attachData in pairs(frame.attachments) do
                if attachData.worldX and attachData.worldY then
                    -- Debug check for NaN values before conversion (removed for performance)
                    
                    local asepriteX, asepriteY = spineToAsepriteCoords(
                        attachData.worldX, attachData.worldY,
                        rootPosition.x, rootPosition.y
                    )
                    
                    -- Debug check for NaN values after conversion (removed for performance)
                    
                    attachData.asepriteX = asepriteX
                    attachData.asepriteY = asepriteY
                    attachData.asepriteRotation = spineToAsepriteRotation(attachData.worldRotation or 0)
                    -- Preserve visibility information
                    -- attachData.visible and attachData.activeName are already set
                end
            end
        end
    end
    
    return animationData
end

-- RotSprite transformation functions using Aseprite's built-in RotSprite algorithm
local function applyRotSpriteTransform(sourceImage, asepriteX, asepriteY, asepriteRotation, asepriteScaleX, asepriteScaleY)
    if not sourceImage then
        return nil
    end
    
    -- Prepare transformation parameters
    local scaleX = math.abs(asepriteScaleX or 1)
    local scaleY = math.abs(asepriteScaleY or 1)
    local rotation = asepriteRotation or 0
    
    -- Start with the source image
    local transformedImage = sourceImage:clone()
    
    -- Calculate final transformed dimensions considering both scaling and rotation
    local w, h = sourceImage.width, sourceImage.height
    local rotRad = math.rad(rotation)
    local cos_r = math.abs(math.cos(rotRad))
    local sin_r = math.abs(math.sin(rotRad))
    
    -- Calculate the bounding box after rotation and scaling
    local scaledW = w * scaleX
    local scaledH = h * scaleY
    local finalWidth = math.ceil(scaledW * cos_r + scaledH * sin_r)
    local finalHeight = math.ceil(scaledW * sin_r + scaledH * cos_r)
    
    -- If we need both scaling and rotation, use RotSprite algorithm
    if (math.abs(scaleX - 1) > 0.01 or math.abs(scaleY - 1) > 0.01 or math.abs(rotation) > 0.5) then
        -- Method 1: Try using RotSprite resize method for combined transform
        -- First, we'll upscale to handle rotation precision better
        local upscaleFactor = 4  -- Upscale factor for better rotation quality
        local tempWidth = math.max(1, math.floor(w * upscaleFactor))
        local tempHeight = math.max(1, math.floor(h * upscaleFactor))
        
        -- Step 1: Upscale using RotSprite
        if tempWidth ~= w or tempHeight ~= h then
            transformedImage:resize{
                width = tempWidth,
                height = tempHeight,
                method = 'rotsprite'
            }
        end
        
        -- Step 2: Apply rotation through matrix transformation and then use RotSprite to get final size
        if math.abs(rotation) > 0.5 then
            -- Calculate rotated dimensions for upscaled image
            local upscaledRotatedWidth = math.ceil(tempWidth * cos_r + tempHeight * sin_r)
            local upscaledRotatedHeight = math.ceil(tempWidth * sin_r + tempHeight * cos_r)
            
            -- Create rotated image using pixel-by-pixel rotation (since Aseprite doesn't have direct rotation)
            local rotatedImage = Image(upscaledRotatedWidth, upscaledRotatedHeight, sourceImage.colorMode)
            local centerX, centerY = upscaledRotatedWidth / 2, upscaledRotatedHeight / 2
            local srcCenterX, srcCenterY = tempWidth / 2, tempHeight / 2
            
            local cos_rot = math.cos(rotRad)
            local sin_rot = math.sin(rotRad)
            
            -- Perform rotation using reverse mapping
            for y = 0, upscaledRotatedHeight - 1 do
                for x = 0, upscaledRotatedWidth - 1 do
                    local dx = x - centerX
                    local dy = y - centerY
                    
                    -- Reverse rotation to find source pixel
                    local srcX = dx * cos_rot + dy * sin_rot + srcCenterX
                    local srcY = -dx * sin_rot + dy * cos_rot + srcCenterY
                    
                    local srcXInt = math.floor(srcX + 0.5)
                    local srcYInt = math.floor(srcY + 0.5)
                    
                    if srcXInt >= 0 and srcXInt < tempWidth and srcYInt >= 0 and srcYInt < tempHeight then
                        local pixel = transformedImage:getPixel(srcXInt, srcYInt)
                        rotatedImage:putPixel(x, y, pixel)
                    end
                end
            end
            
            transformedImage = rotatedImage
        end
        
        -- Step 3: Scale down to final size using RotSprite algorithm
        local targetWidth = math.max(1, math.floor(finalWidth))
        local targetHeight = math.max(1, math.floor(finalHeight))
        
        if transformedImage.width ~= targetWidth or transformedImage.height ~= targetHeight then
            transformedImage:resize{
                width = targetWidth,
                height = targetHeight,
                method = 'rotsprite'
            }
        end
        
    elseif math.abs(scaleX - 1) > 0.01 or math.abs(scaleY - 1) > 0.01 then
        -- Only scaling, no rotation
        local newWidth = math.max(1, math.floor(w * scaleX))
        local newHeight = math.max(1, math.floor(h * scaleY))
        transformedImage:resize{
                width = newWidth,
                height = newHeight,
                method = 'rotsprite'
            }
    end
    
    -- Calculate final position (center the transformed image at target position)
    local finalPosition = Point(
        math.floor(asepriteX - transformedImage.width / 2),
        math.floor(asepriteY - transformedImage.height / 2)
    )
    
    -- Debug output for position calculation in applyRotSpriteTransform (removed for performance)
    
    return transformedImage, finalPosition
end

-- Generate animation frames in Aseprite
local function generateAsepriteAnimation(animationData, selectedAnim)
    if not animationData or not animationData[selectedAnim] then
        return false
    end
    
    local animation = animationData[selectedAnim]
    if not animation.frames or #animation.frames == 0 then
        return false
    end
    
    if not app.activeSprite then
        return false
    end
    
    local sprite = app.activeSprite
    local frameCount = #animation.frames
    
    -- Store current frame selection to restore later
    local currentFrame = app.activeFrame
    
    -- Store original images before any transformation
    local originalImages = {}
    
    -- Helper function to recursively collect all layers (including those in groups)
    local function collectAllLayers(layers, result)
        result = result or {}
        for _, layer in ipairs(layers) do
            if layer.isGroup then
                -- Recursively collect layers from groups
                collectAllLayers(layer.layers, result)
            else
                -- Try to access cel in frame 1 to determine if it's an image layer
                local cel = layer:cel(1)
                if cel and cel.image then
                    -- Store the image for all layers (we'll check for attachments later)
                    result[layer.name] = {
                        image = cel.image:clone(),  -- Clone the original image
                        position = cel.position,
                        layer = layer  -- Store reference to the actual layer
                    }
                end
            end
        end
        return result
    end
    
    -- Collect all layers including those in groups
    originalImages = collectAllLayers(sprite.layers)
    
    if next(originalImages) == nil then
        return false
    end
    
    -- Calculate starting frame index (add new frames at the end)
    local startFrameIndex = #sprite.frames + 1
    
    -- Store existing tags that end at the last frame to preserve their ranges
    local tagsToPreserve = {}
    local lastFrameIndex = #sprite.frames
    for _, tag in ipairs(sprite.tags) do
        if tag.toFrame.frameNumber == lastFrameIndex then
            table.insert(tagsToPreserve, {
                tag = tag,
                originalEndFrame = lastFrameIndex
            })
        end
    end
    
    -- Create new frames at the end of the sprite
    for i = 1, frameCount do
        sprite:newFrame()
    end
    
    -- Process each frame
    for frameIndex, frameData in ipairs(animation.frames) do
        -- Calculate actual frame index in sprite (starting from the end)
        local actualFrameIndex = startFrameIndex + frameIndex - 1
        
        -- Process each layer that has an original image AND has a corresponding attachment
        for layerName, originalData in pairs(originalImages) do
            -- Find if this layer has attachment data in this frame
            local attachData = nil
            local attachName = layerName
            
            -- Step 1: Try exact match first (highest priority)
            for frameAttachName, frameAttachData in pairs(frameData.attachments) do
                if frameAttachName == layerName then
                    attachData = frameAttachData
                    attachName = frameAttachName
                    break
                end
            end
            
            -- Step 2: If no exact match, try case-insensitive exact match
            if not attachData then
                for frameAttachName, frameAttachData in pairs(frameData.attachments) do
                    if string.lower(frameAttachName) == string.lower(layerName) then
                        attachData = frameAttachData
                        attachName = frameAttachName
                        break
                    end
                end
            end
            
            -- Step 3: If still no match, try removing common prefixes/suffixes and exact match
            if not attachData then
                local cleanLayerName = layerName:gsub("^[%w_]*[_%-]", ""):gsub("[_%-][%w_]*$", "")
                for frameAttachName, frameAttachData in pairs(frameData.attachments) do
                    local cleanAttachName = frameAttachName:gsub("^[%w_]*[_%-]", ""):gsub("[_%-][%w_]*$", "")
                    if cleanLayerName == cleanAttachName then
                        attachData = frameAttachData
                        attachName = frameAttachName
                        break
                    end
                end
            end
            
            -- Step 4: Only as last resort, try partial matches with length constraints
            if not attachData then
                for frameAttachName, frameAttachData in pairs(frameData.attachments) do
                    -- Only allow partial matches if the shorter name is at least 50% of the longer name
                    local minLen = math.min(#layerName, #frameAttachName)
                    local maxLen = math.max(#layerName, #frameAttachName)
                    if minLen / maxLen >= 0.5 then
                        -- Check if one name completely contains the other (but not as substring)
                        if (layerName:find("^" .. frameAttachName .. "[_%-]") or 
                            layerName:find("[_%-]" .. frameAttachName .. "$") or
                            frameAttachName:find("^" .. layerName .. "[_%-]") or 
                            frameAttachName:find("[_%-]" .. layerName .. "$")) then
                            attachData = frameAttachData
                            attachName = frameAttachName
                            break
                        end
                    end
                end
            end
            
            -- Only process layers that have corresponding attachments
            if attachData and attachData.asepriteX and attachData.asepriteY then
                -- Use the stored layer reference (supports layers in groups)
                local targetLayer = originalData.layer
                
                if targetLayer then
                    -- Check if attachment should be visible
                    local isVisible = attachData.visible
                    if isVisible == nil then
                        isVisible = true  -- Default to visible if not specified
                    end
                    
                    if isVisible then
                        -- Apply RotSprite transformation to the original image
                        local transformedImage, position = applyRotSpriteTransform(
                            originalData.image,  -- Use original unmodified image
                            attachData.asepriteX,
                            attachData.asepriteY,
                            attachData.asepriteRotation or 0,
                            attachData.worldScaleX or 1,
                            attachData.worldScaleY or 1
                        )
                        
                        if transformedImage and position then
                            -- Debug output for position analysis
                            local debugMsg = string.format(
                                "Frame %d, Layer '%s':\n" ..
                                "  Attachment: %s\n" ..
                                "  Aseprite coords: (%.2f, %.2f)\n" ..
                                "  Rotation: %.2f°\n" ..
                                "  Scale: (%.2f, %.2f)\n" ..
                                "  Image size: %dx%d\n" ..
                                "  Final position: (%d, %d)\n" ..
                                "  Position calculation: center(%.2f, %.2f) - half_size(%d, %d) = final(%d, %d)",
                                actualFrameIndex, layerName, attachName,
                                attachData.asepriteX or 0, attachData.asepriteY or 0,
                                attachData.asepriteRotation or 0,
                                attachData.worldScaleX or 1, attachData.worldScaleY or 1,
                                transformedImage.width, transformedImage.height,
                                position.x, position.y,
                                attachData.asepriteX or 0, attachData.asepriteY or 0,
                                math.floor(transformedImage.width / 2), math.floor(transformedImage.height / 2),
                                position.x, position.y
                            )
                            
                            -- Check for suspicious positions (near top-left corner)
                            if position.x <= 10 and position.y <= 10 then
                                debugMsg = "*** POTENTIAL ISSUE - Drawing near top-left corner! ***\n" .. debugMsg
                                -- Debug output (removed for performance)
                            end
                            
                            -- Create new cel in the calculated frame position
                            local cel = sprite:newCel(targetLayer, actualFrameIndex)
                            if cel then
                                cel.image = transformedImage
                                cel.position = position
                            end
                        else
                            -- Debug output for failed transformation (removed for performance)
                        end
                    else
                        -- Attachment is hidden - create an empty cel to ensure the layer is hidden in this frame
                        -- This explicitly clears any content that might exist
                        local existingCel = targetLayer:cel(actualFrameIndex)
                        if existingCel then
                            -- Delete existing cel if it exists
                            sprite:deleteCel(existingCel)
                        end
                        -- Note: We don't create a new cel, leaving the frame empty for this layer
                        -- Debug output: Attachment hidden, cel cleared (removed for performance)
                    end
                end
            else
                -- If no matching attachment found, clear this layer in this frame
                -- This ensures layers without corresponding attachments are hidden
                local targetLayer = originalData.layer  -- Use stored layer reference (supports layers in groups)
                
                if targetLayer then
                    local existingCel = targetLayer:cel(actualFrameIndex)
                    if existingCel then
                        -- Delete existing cel if it exists
                        sprite:deleteCel(existingCel)
                    end
                    -- Debug output: No matching attachment found, cel cleared (removed for performance)
                end
            end
        end
        
        -- Set frame duration to 100ms (0.1 seconds)
        local targetFrame = sprite.frames[actualFrameIndex]
        if targetFrame then
            targetFrame.duration = 1/fps
        end
    end
    
    -- Restore the end frames of existing tags that were at the last frame before adding new frames
    for _, preserveInfo in ipairs(tagsToPreserve) do
        preserveInfo.tag.toFrame = sprite.frames[preserveInfo.originalEndFrame]
    end
    
    -- Create a new tag for the generated animation frames
    local endFrameIndex = startFrameIndex + frameCount - 1
    sprite:newTag(startFrameIndex, endFrameIndex)
    local newTag = sprite.tags[#sprite.tags]  -- Get the newly created tag
    if newTag then
        newTag.name = selectedAnim
        -- Optional: set a color for the tag to make it distinctive
        newTag.color = Color{r=100, g=150, b=255}  -- Light blue color
    end
    
    -- Restore original frame selection
    app.activeFrame = currentFrame
    
    return true
end

-- Calculate root bone position in Aseprite coordinate system using setup pose
local function calculateRootPosition(animationData, selectedAnim, boneSystem, data)
    if not data or not data.skins or not data.skins[1] or not data.skins[1].attachments then
        return nil
    end
    local referenceAttachment = nil
    local referenceName = nil
    local setupAttachmentData = nil
    
    -- Select the first available attachment (but not bones starting with "skip")
    for slotName, attachments in pairs(data.skins[1].attachments) do
        for attachName, attachment in pairs(attachments) do
            -- Find the corresponding bone
            local attachmentBone = nil
            if data.slots then
                for _, slot in ipairs(data.slots) do
                    if slot.name == slotName then
                        attachmentBone = boneSystem.bonesByName[slot.bone]
                        break
                    end
                end
            end
            -- Only use bones that do not start with "skip"
            if attachmentBone and not string.find(string.lower(attachmentBone.name), "^skip") then
                referenceAttachment = attachment
                referenceName = attachName
                setupAttachmentData = {
                    x = attachment.x or 0,
                    y = attachment.y or 0,
                    rotation = attachment.rotation or 0,
                    scaleX = attachment.scaleX or 1,
                    scaleY = attachment.scaleY or 1,
                    bone = attachmentBone
                }
                break
            end
        end
        if setupAttachmentData then break end
    end
    if not setupAttachmentData then
        return nil
    end
    
    -- Calculate the world coordinates of the attachment in the setup pose
    -- First, set all bones to the setup pose
    for _, bone in ipairs(boneSystem.bones) do
        bone.x = bone.setupX
        bone.y = bone.setupY
        bone.rotation = bone.setupRotation
        bone.scaleX = bone.setupScaleX
        bone.scaleY = bone.setupScaleY
    end
    
    -- Calculate the world transformation in the setup pose
    calculateBoneTransforms(boneSystem)
    
    -- Calculate the world coordinates of the attachment
    local attachmentBone = setupAttachmentData.bone
    local boneWorldMatrix = attachmentBone.worldMatrix
    
    -- Create the local transformation matrix of the attachment
    local cos_r = math.cos(math.rad(setupAttachmentData.rotation))
    local sin_r = math.sin(math.rad(setupAttachmentData.rotation))
    
    local attachLocalMatrix = {
        a = cos_r * setupAttachmentData.scaleX,
        b = -sin_r * setupAttachmentData.scaleX,
        c = sin_r * setupAttachmentData.scaleY,
        d = cos_r * setupAttachmentData.scaleY,
        tx = setupAttachmentData.x,
        ty = setupAttachmentData.y
    }
    
    -- Calculate the world transformation matrix of the attachment
    local attachWorldMatrix = {
        a = boneWorldMatrix.a * attachLocalMatrix.a + boneWorldMatrix.b * attachLocalMatrix.c,
        b = boneWorldMatrix.a * attachLocalMatrix.b + boneWorldMatrix.b * attachLocalMatrix.d,
        c = boneWorldMatrix.c * attachLocalMatrix.a + boneWorldMatrix.d * attachLocalMatrix.c,
        d = boneWorldMatrix.c * attachLocalMatrix.b + boneWorldMatrix.d * attachLocalMatrix.d,
        tx = boneWorldMatrix.a * attachLocalMatrix.tx + boneWorldMatrix.b * attachLocalMatrix.ty + boneWorldMatrix.tx,
        ty = boneWorldMatrix.c * attachLocalMatrix.tx + boneWorldMatrix.d * attachLocalMatrix.ty + boneWorldMatrix.ty
    }
    
    local setupWorldX = attachWorldMatrix.tx
    local setupWorldY = attachWorldMatrix.ty
    
    -- Try to find the corresponding image/layer in Aseprite
    if not app.activeSprite then
        return nil
    end
    
    local sprite = app.activeSprite
    local referenceLayer = nil
    
    -- Helper function to recursively search for layer (including those in groups)
    local function findLayerByName(layers, targetName)
        for _, layer in ipairs(layers) do
            if layer.isGroup then
                -- Recursively search in groups
                local found = findLayerByName(layer.layers, targetName)
                if found then return found end
            else
                -- Check if layer name matches
                if layer.name == targetName or layer.name:find(targetName) then
                    return layer
                end
            end
        end
        return nil
    end
    
    -- Look for a layer that matches the attachment name (including in groups)
    referenceLayer = findLayerByName(sprite.layers, referenceName)
    
    if not referenceLayer then
        return nil
    end
    
    -- Get the bounds of the reference layer's content
    local cel = referenceLayer:cel(1)
    if not cel then
        return nil
    end
    
    local celBounds = cel.bounds
    if celBounds.isEmpty then
        return nil
    end
    
    local layerCenterX = celBounds.x + celBounds.width / 2
    local layerCenterY = celBounds.y + celBounds.height / 2
    
    -- Calculate root position using setup coordinates (Y axis flipped for coordinate system conversion)
    local rootX = layerCenterX - setupWorldX
    local rootY = layerCenterY + setupWorldY

    return {
        x = rootX,
        y = rootY,
        referenceAttachment = referenceName,
        referenceLayer = referenceLayer.name,
        coordinateSystemNote = "Y axis flipped from Spine to Aseprite, using setup pose"
    }
end

-- Main function
local function convertSpineToAseprite()
    local dlg = Dialog{
        title = "Spine to Aseprite Converter",
        onclose = function() end
    }
    
    local animationNames = {}
    local data = nil
    
    -- Function to update animation list
    local function updateAnimationList()
        local jsonPath = dlg.data.jsonFile
        if not jsonPath or jsonPath == "" then
            dlg:modify{
                id = "selectedAnimation",
                options = {"No JSON file selected"},
                option = "No JSON file selected"
            }
            dlg:modify{
                id = "process",
                enabled = false
            }
            return
        end
        
        -- Read JSON file
        local file = io.open(jsonPath, "r")
        if not file then
            dlg:modify{
                id = "selectedAnimation", 
                options = {"Error: Cannot open file"},
                option = "Error: Cannot open file"
            }
            dlg:modify{
                id = "process",
                enabled = false
            }
            return
        end
        
        local jsonContent = file:read("*all")
        file:close()
        
        -- Parse JSON
        data = parseJSON(jsonContent)
        if data and data.skeleton and tonumber(data.skeleton.fps) and tonumber(data.skeleton.fps) > 0 then
                fps = tonumber(data.skeleton.fps)
        end

        if not data or not data.animations then
            dlg:modify{
                id = "selectedAnimation",
                options = {"Error: No animations found"},
                option = "Error: No animations found"
            }
            dlg:modify{
                id = "process",
                enabled = false
            }
            return
        end
        
        -- Get animation names
        animationNames = {}
        for animName, _ in pairs(data.animations) do
            table.insert(animationNames, animName)
        end
        table.sort(animationNames)
        
        if #animationNames == 0 then
            dlg:modify{
                id = "selectedAnimation",
                options = {"No animations found"},
                option = "No animations found"
            }
            dlg:modify{
                id = "process",
                enabled = false
            }
        else
            dlg:modify{
                id = "selectedAnimation",
                options = animationNames,
                option = animationNames[1]
            }
            dlg:modify{
                id = "process",
                enabled = true
            }
        end
    end
    
    dlg:file{
        id = "jsonFile",
        label = "Spine JSON File:",
        title = "Select Spine JSON file",
        open = true,
        filetypes = {"json"},
        onchange = updateAnimationList
    }



    dlg:combobox{
        id = "selectedAnimation",
        label = "Animation:",
        options = {"Select a JSON file first"},
        option = "Select a JSON file first"
    }
    
    dlg:button{
        id = "process",
        text = "Process Animation",
        enabled = false,
        onclick = function()
            local selectedAnim = dlg.data.selectedAnimation
            -- Read fps directly from json.skeleton.fps
            local fps = 10
            if data and data.skeleton and tonumber(data.skeleton.fps) and tonumber(data.skeleton.fps) > 0 then
                fps = tonumber(data.skeleton.fps)
            end

            if not data or not selectedAnim or selectedAnim == "Select a JSON file first" then
                app.alert("Please select a valid JSON file and animation")
                return
            end

            -- Build bone hierarchy
            local boneSystem = buildBoneHierarchy(data)
            if not boneSystem then
                app.alert("Failed to build bone hierarchy")
                return
            end

            -- Calculate initial bone transforms
            calculateBoneTransforms(boneSystem)

            -- Process only the selected animation
            local selectedAnimData = {}
            selectedAnimData[selectedAnim] = data.animations[selectedAnim]

            local tempData = {
                animations = selectedAnimData,
                bones = data.bones,
                slots = data.slots,
                skins = data.skins
            }

            -- Set global fps variable for processAnimationData to read
            if not _G then _G = {} end
            _G.__aseprite_spine2aseprite_fps = fps
            local animationData = processAnimationData(tempData, boneSystem)
            _G.__aseprite_spine2aseprite_fps = nil
            if not animationData then
                app.alert("Failed to process animation data")
                return
            end

            -- Calculate root position in Aseprite coordinate system
            local rootPosition = calculateRootPosition(animationData, selectedAnim, boneSystem, data)
            if rootPosition then
                -- Store root position for further processing
                animationData[selectedAnim].rootPosition = rootPosition

                -- Convert animation coordinates from Spine to Aseprite system
                animationData = convertAnimationToAsepriteCoords(animationData, rootPosition)

                -- Generate actual animation frames in Aseprite (wrapped in transaction for undo)
                app.transaction(function()
                    local success = generateAsepriteAnimation(animationData, selectedAnim)
                    if success then
                        app.alert("Animation generated successfully!")
                    else
                        error("Animation generation failed")  -- This will rollback the transaction
                    end
                end)
            else
                app.alert("Could not calculate root position. Make sure the sprite layers match attachment names.")
            end

            dlg:close()
        end
    }
    
    dlg:button{
        id = "cancel",
        text = "Cancel",
        onclick = function()
            dlg:close()
        end
    }
    
    dlg:show()
end

-- Run the converter
convertSpineToAseprite()
