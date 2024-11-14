local sprite = app.activeSprite
local cels = app.range.cels

-- Check if at least two cels are selected
if #cels < 2 then
    print("Please select a series of cels from the same layer.")
    return
end

-- Get the layer of the first cel
local firstLayer = cels[1].layer
local samelayer = true
-- Check if all other cels are on the same layer
for i = 2, #cels do
    if cels[i].layer ~= firstLayer then
        samelayer = false
        print("Warning: Selected Cels are not on the same layer!")
        return
    end
end



-- Run script only if a series of cels is selected
if sprite and #cels >= 2 and samelayer then


    
    -- Save original cel Position and image for cancel changes
    local celPosition = {}
    for _, cel in ipairs(cels) do
        table.insert(celPosition , cel.position)
    end

    local celimage = {}
    for _, cel in ipairs(cels) do
        table.insert(celimage, Image(cel.image))
    end

    -- Cancel changes
    local function cancelAnimation()
        for i=1 ,#cels do
            cels[i].image:clear()
            cels[i].image:drawImage(celimage[i],0, 0)
            cels[i].position = Point(celPosition [i].x, celPosition [i].y)
        end
    end

    -- Check if the Apply button is clicked
    local clickApply = false


    
    -- Since the cels in cels are not ordered by frame number, retrieve the cel of the first frame and the cel of the last frame.
    local minFrameNumber = math.huge
    local maxFrameNumber = -math.huge

    -- get minframeNumber and minFrameCel
    for _, cel in ipairs(cels) do
        local frameNumber = cel.frame.frameNumber
                
        if frameNumber < minFrameNumber then
            minFrameNumber = frameNumber
        end
    end
    
    -- get maxFrameNumber and maxFrameCel
    for _, cel in ipairs(cels) do
        local frameNumber = cel.frame.frameNumber

        if frameNumber > maxFrameNumber then
            maxFrameNumber = frameNumber
        end
    end


    -- Save the position of each cel, sort by frame number.
    local celPositionbyFrames = {}
    for i = 1,#cels do
        for _, cel in ipairs(cels) do
            if cel.frame.frameNumber == minFrameNumber + i - 1 then
                table.insert(celPositionbyFrames , cel.position)
                break
            end
        end
    end

    -- Save the image of each cel, sort by frame number.
    local celimagebyFrames = {}
    for i = 1,#cels do
        for _, cel in ipairs(cels) do
            if cel.frame.frameNumber == minFrameNumber + i - 1 then
                local fullImage = Image(sprite.spec)  
                fullImage:drawImage(cel.image, cel.bounds.x, cel.bounds.y)  
                table.insert(celimagebyFrames , fullImage)
                break
            end
        end
    end

    app.userData = app.userData or {}
    local previousSettings = app.userData.dialogSettings or {
        shiftAmount = 0,
    }

    local dlg = Dialog{
        title = "circular shift",
        onclose = function()
            if clickApply == false then   
                cancelAnimation()
            end
            app.refresh()
        end
    }

    -- crop cels
    local function calculateTrimBounds(image)
        local minX, minY, maxX, maxY = image.width, image.height, 0, 0
        local hasContent = false
    
      
        for y = 0, image.height - 1 do
            for x = 0, image.width - 1 do
                local pixel = image:getPixel(x, y)
                if app.pixelColor.rgbaA(pixel) > 0 then 
                    minX = math.min(minX, x)
                    minY = math.min(minY, y)
                    maxX = math.max(maxX, x)
                    maxY = math.max(maxY, y)
                    hasContent = true
                end
            end
        end
    
        if hasContent then
            return minX, minY, maxX, maxY
        else
            return nil 
        end
    end

    

    local function PreApply()
        local shiftAmount = tonumber(dlg.data.shiftAmount)
        if not shiftAmount then
            return app.alert("Invalid Shift Amount")
        else
            for i=1 ,#cels do
                cels[i].image:clear()
                if (cels[i].frame.frameNumber -shiftAmount >= minFrameNumber ) and (cels[i].frame.frameNumber -shiftAmount <= maxFrameNumber) then
                    cels[i].image = Image(sprite.spec)
                    cels[i].image:drawImage(celimagebyFrames[cels[i].frame.frameNumber - minFrameNumber + 1 - shiftAmount],0, 0)
                    cels[i].position = Point(0,0)
                elseif cels[i].frame.frameNumber -shiftAmount < minFrameNumber then
                    cels[i].image = Image(sprite.spec)
                    cels[i].image:drawImage(celimagebyFrames[cels[i].frame.frameNumber - minFrameNumber + 1 - shiftAmount + maxFrameNumber - minFrameNumber + 1],0, 0)
                    cels[i].position = Point(0,0)
                else
                    cels[i].image = Image(sprite.spec)
                    cels[i].image:drawImage(celimagebyFrames[cels[i].frame.frameNumber - minFrameNumber + 1 - shiftAmount - (maxFrameNumber - minFrameNumber + 1)],0, 0)
                    cels[i].position = Point(0,0)
                end
            end

            --crop cels
            for _, cel in ipairs(cels) do
                local image = cel.image
                local minX, minY, maxX, maxY = calculateTrimBounds(image)

                if minX then 
                    local newWidth = maxX - minX + 1
                    local newHeight = maxY - minY + 1

                    local trimmedImage = Image(newWidth, newHeight)
                    trimmedImage:drawImage(image, -minX, -minY)
                    cel.image = trimmedImage

                    cel.position = Point(cel.position.x + minX, cel.position.y + minY)
                end
            end




            app.refresh()
        end
    end

    -- Create dialog
    dlg:label{
        id = "shiftAmountlabel",
        text = "Shift Amount"
        }
    dlg:newrow()
    dlg:slider{
        id = "shiftAmount",
        min = -(maxFrameNumber-minFrameNumber+1),
        max = maxFrameNumber-minFrameNumber+1,
        value = previousSettings.shiftAmount or 0,
        onchange=function ()
            PreApply()
        end
    }
    PreApply()
    dlg:button{
        text = "Apply",
        onclick = function()
            clickApply = true
            app.userData.dialogSettings = {shiftAmount = 0,}
            PreApply()
            dlg:close()
        end
    }

    dlg:show{wait = false}

end
