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


    -- Since the cels in cels are not ordered by frame number, retrieve the cel of the first frame and the cel of the last frame.
    local minFrameCel = nil
    local minFrameNumber = math.huge
    local maxFrameCel = nil
    local maxFrameNumber = -math.huge


    -- Save original cel Position and size for cancel changes
    local celPosition = {}
    for _, cel in ipairs(cels) do
        table.insert(celPosition , cel.position)
    end
    --local celSize = {}
    --for _, cel in ipairs(cels) do
    --    table.insert(celSize , Point(cel.image.width,cel.image.height))
    --end

    local celimage = {}
    for _, cel in ipairs(cels) do
        table.insert(celimage, Image(cel.image))
    end

    -- Cancel changes on position and size
    local function cancelAnimation()
        for i=1 ,#cels do
            cels[i].image:clear()
            cels[i].image:drawImage(celimage[i],0, 0)
            cels[i].position = Point(celPosition [i].x, celPosition [i].y)
        end
    end
                
    -- Check if the Apply button is clicked
    local clickApply = false

    -- get minframeNumber and minFrameCel
    for _, cel in ipairs(cels) do
        local frameNumber = cel.frame.frameNumber
                
        if frameNumber < minFrameNumber then
            minFrameNumber = frameNumber
                    minFrameCel = cel
        end
    end
    
    -- get maxFrameNumber and maxFrameCel
    for _, cel in ipairs(cels) do
        local frameNumber = cel.frame.frameNumber

        if frameNumber > maxFrameNumber then
            maxFrameNumber = frameNumber
            maxFrameCel = cel
        end
    end




    -- t(after easing) of each cel when using bezier
    local bezierT = {}    

    -- Get point on a bezier curve based on t
    local function bezier(t, StartX, StartY, ControlX1, ControlY1, ControlX2, ControlY2, EndX, EndY)
        local x = (1 - t)^3 * StartX + 3 * (1 - t)^2 * t * ControlX1 + 3 * (1 - t) * t^2 * ControlX2 + t^3 * EndX
        local y = (1 - t)^3 * StartY + 3 * (1 - t)^2 * t * ControlY1 + 3 * (1 - t) * t^2 * ControlY2 + t^3 * EndY
        return { x = x, y = y }
    end


    -- Create a new layer for trail
    local trailLayer = sprite:newLayer()
    trailLayer.name = "Trailing Effect"


    -- Initialize or read previous userData settings
    app.userData = app.userData or {}
    local previousSettings = app.userData.dialogSettings or {
        easingType = "easeInQuad",
        useBezier = false,
        changeXPosition = true,
        changeYPosition = true,
        changeXSize = true,
        changeYSize = true,
        controlX1 = 0,
        controlY1 = 0,
        controlX2 = 0,
        controlY2 = 0,
        trailNumSteps = 5,
        minTrailOpacity = 0,
        maxTrailOpacity = 255,
        minTrailLength = 0,
        maxTrailLength = 2,
    
    }





    -- Define available easing types and their descriptions
    local easingTypes = {
        "linear",
        "easeInSine", "easeOutSine", "easeInOutSine",
        "easeInQuad", "easeOutQuad", "easeInOutQuad",
        "easeInCubic", "easeOutCubic", "easeInOutCubic",
        "easeInQuart", "easeOutQuart", "easeInOutQuart",
        "easeInQuint", "easeOutQuint", "easeInOutQuint",
        "easeInExponential", "easeOutExponential", "easeInOutExponential",
        "easeInCircular", "easeOutCircular", "easeInOutCircular",
        "easeInBack", "easeOutBack", "easeInOutBack",
        "easeInElastic", "easeOutElastic", "easeInOutElastic",
        "easeInBounce", "easeOutBounce", "easeInOutBounce",
        "pingpong",
    }

    local easingDescriptions = {
        linear = "Linear: Constant speed",
        easeInQuad = "Ease In Quad: Slow start, gradually accelerates",
        easeOutQuad = "Ease Out Quad: Fast start, gradually decelerates",
        easeInOutQuad = "Ease In-Out Quad: Slow start and end, fast in the middle",
        easeInCubic = "Ease In Cubic: Slow start, accelerates quickly",
        easeOutCubic = "Ease Out Cubic: Fast start, decelerates at the end",
        easeInOutCubic = "Ease In-Out Cubic: Accelerates in the middle, slow start and end",
        pingpong = "Pingpong: Back and forth motion",
        easeInQuart = "Ease In Quart: Slow start, accelerates rapidly",
        easeOutQuart = "Ease Out Quart: Fast start, decelerates rapidly",
        easeInOutQuart = "Ease In-Out Quart: Slow start and end, rapid in the middle",
        easeInQuint = "Ease In Quint: Very slow start, then rapidly accelerates",
        easeOutQuint = "Ease Out Quint: Fast start, slows down significantly at the end",
        easeInOutQuint = "Ease In-Out Quint: Slow start and end, fast in the middle",
        easeInBounce = "Ease In Bounce: Starts slow, bounces as it accelerates",
        easeOutBounce = "Ease Out Bounce: Starts fast, then bounces at the end",
        easeInOutBounce = "Ease In-Out Bounce: Bounces at both ends, smooth in the middle",
        easeInElastic = "Ease In Elastic: Starts slow, stretches out, then snaps back",
        easeOutElastic = "Ease Out Elastic: Starts fast, stretches, then snaps back",
        easeInOutElastic = "Ease In-Out Elastic: Stretching motion both ways, smoother in the middle",
        easeInExponential = "Ease In Exponential: Slow start, rapidly increases",
        easeOutExponential = "Ease Out Exponential: Fast start, rapidly decreases",
        easeInOutExponential = "Ease In-Out Exponential: Slow start and end, rapid in the middle",
        easeInSine = "Ease In Sine: Smooth curve start, gradually rises",
        easeOutSine = "Ease Out Sine: Smooth curve end, gradually lowers",
        easeInOutSine = "Ease In-Out Sine: Smooth start and end, fast in the middle",
        easeInCircular = "Ease In Circular: Slow start, rises quickly",
        easeOutCircular = "Ease Out Circular: Fast start, curves to the end",
        easeInOutCircular = "Ease In-Out Circular: Slow start and end, smooth in the middle",
        easeInBack = "Ease In Back: Starts slow, overshoots slightly",
        easeOutBack = "Ease Out Back: Fast start, overshoots slightly at the end",
        easeInOutBack = "Ease In-Out Back: Slow start and end, overshoots in the middle",
    }

    -- Animation function
    local function animateCels(easingType, changeXPosition, changeYPosition, changeXSize, changeYSize, controlX1, controlY1, controlX2, controlY2, useBezier)
        


        -- Get starting and ending positions and size
        local startCel = minFrameCel 
        local endCel = maxFrameCel

        local startX, startY = startCel.position.x, startCel.position.y
        local endX, endY = endCel.position.x, endCel.position.y
        --local startWidth, startHeight = startCel.image.width, startCel.image.height
        --local endWidth, endHeight = endCel.image.width, endCel.image.height

        -- Define the pow function if not available
        local function pow(x, y)
            return x ^ y
        end

        -- Define easing functions
        local function easing(t, type)
        if type == "linear" then
            return t
        elseif type == "easeInQuad" then
            return t * t
        elseif type == "easeOutQuad" then
            return t * (2 - t)
        elseif type == "easeInOutQuad" then
            if t < 0.5 then return 2 * t * t else return -1 + (4 - 2 * t) * t end
        elseif type == "easeInCubic" then
            return t * t * t
        elseif type == "easeOutCubic" then
            t = t - 1
            return t * t * t + 1
        elseif type == "easeInOutCubic" then
            if t < 0.5 then return 4 * t * t * t else return (t - 1) * (2 * t - 2) * (2 * t - 2) + 1 end
        elseif type == "pingpong" then
            if t < 0.5 then
                return 2 * t  -- First half, moving towards end position
            else
                return 2 - 2 * t  -- Second half, returning to start position
            end
        elseif type == "easeInQuart" then
            return t * t * t * t
        elseif type == "easeOutQuart" then
            t = t - 1
            return 1 - t * t * t * t
        elseif type == "easeInOutQuart" then
            if t < 0.5 then return 8 * t * t * t * t else return 1 - 8 * (t - 1) * (t - 1) * (t - 1) * (t - 1) end
        elseif type == "easeInQuint" then
            return t * t * t * t * t
        elseif type == "easeOutQuint" then
            t = t - 1
            return t * t * t * t * t + 1
        elseif type == "easeInOutQuint" then
            if t < 0.5 then return 16 * t * t * t * t * t else t = t - 1; return 1 + 16 * t * t * t * t * t end
        elseif type == "easeInBounce" then
            return 1 - easing(1 - t, "easeOutBounce")
        elseif type == "easeOutBounce" then
            if t < 4 / 11 then
                return (121 * t * t) / 16
            elseif t < 8 / 11 then
                return (363 / 40 * t * t) - (99 / 10 * t) + 17 / 5
            elseif t < 9 / 10 then
                return (4356 / 361 * t * t) - (35442 / 1805 * t) + 16061 / 1805
            else
                return (54 / 5 * t * t) - (126 / 5 * t) + 126 / 5
            end
        elseif type == "easeInOutBounce" then
            if t < 0.5 then
                return easing(t * 2, "easeInBounce") * 0.5
            else
                return easing(t * 2 - 1, "easeOutBounce") * 0.5 + 0.5
            end
        elseif type == "easeInElastic" then
            if t == 0 then return 0 end
            if t == 1 then return 1 end
            local p = 0.3
            local s = p / 4
            return -(pow(2, 10 * (t - 1)) * math.sin((t - 1 - s) * (2 * math.pi) / p))
        elseif type == "easeOutElastic" then
            if t == 0 then return 0 end
            if t == 1 then return 1 end
            local p = 0.3
            local s = p / 4
            return (pow(2, -10 * t) * math.sin((t - s) * (2 * math.pi) / p) + 1)
        elseif type == "easeInOutElastic" then
            if t == 0 then return 0 end
            if t == 1 then return 1 end
            local p = 0.3
            local s = p / 4
            if t < 0.5 then
                return -(pow(2, 20 * t - 10) * math.sin((20 * t - 11.125) * (2 * math.pi) / p)) * 0.5
            else
                return (pow(2, -20 * t + 10) * math.sin((20 * t - 11.125) * (2 * math.pi) / p)) * 0.5 + 1
            end
        elseif type == "easeInExponential" then
            return t == 0 and 0 or pow(2, 10 * (t - 1))
        elseif type == "easeOutExponential" then
            return t == 1 and 1 or 1 - pow(2, -10 * t)
        elseif type == "easeInOutExponential" then
            if t == 0 then return 0 end
            if t == 1 then return 1 end
            if t < 0.5 then return pow(2, 20 * t - 10) / 2
            else return (2 - pow(2, -20 * t + 10)) / 2 end
        elseif type == "easeInSine" then
            return 1 - math.cos(t * (math.pi / 2))
        elseif type == "easeOutSine" then
            return math.sin(t * (math.pi / 2))
        elseif type == "easeInOutSine" then
            return -0.5 * (math.cos(math.pi * t) - 1)
        elseif type == "easeInCircular" then
            return 1 - math.sqrt(1 - pow(t, 2))
        elseif type == "easeOutCircular" then
            return math.sqrt(1 - pow(t - 1, 2))
        elseif type == "easeInOutCircular" then
            if t < 0.5 then
                return (1 - math.sqrt(1 - pow(2 * t, 2))) / 2
            else
                return (math.sqrt(1 - pow(-2 * t + 2, 2)) + 1) / 2
            end
        elseif type == "easeInBack" then
            local s = 1.70158
            return t * t * ((s + 1) * t - s)
        elseif type == "easeOutBack" then
            local s = 1.70158
            t = t - 1
            return t * t * ((s + 1) * t + s) + 1
        elseif type == "easeInOutBack" then
            local s = 1.70158
            if t < 0.5 then
                t = t * 2
                return (t * t * ((s * 1.525 + 1) * t - s * 1.525)) / 2
            else
                t = t * 2 - 2
                return (t * t * ((s * 1.525 + 1) * t + s * 1.525) + 2) / 2
            end
        else
            return t  -- Default to linear
        end
        end    
        
        -- Clear bezierT
        bezierT = {}

        -- Change each cell except for first cel and last cel
        for i = minFrameNumber + 1, minFrameNumber + #cels - 2 do
        
            -- Retrieve the cel to be transformed
            local cel = nil
            for _, cel1 in ipairs(cels) do
                if cel1.frame.frameNumber == i then
                    cel = cel1
                    break
                end
            end
        
            -- Normalize progress value
            local t = (i - minFrameNumber) / (#cels - 1)

            -- Apply selected easing curve to adjust t
            t = easing(t, easingType)

            -- Add t to bezierT
            table.insert(bezierT, t) 

            -- Move along Bezier curve
            if useBezier then
                if changeXPosition then
                    -- Calculate new x and y using cubic Bezier formula
                    local newX = (1 - t)^3 * startX + 3 * (1 - t)^2 * t * controlX1 + 3 * (1 - t) * t^2 * controlX2 + t^3 * endX
                    -- Set new position for the cell
                    cel.position = Point(newX, cel.position.y)
                end
                if changeYPosition then
                    local newY = (1 - t)^3 * startY + 3 * (1 - t)^2 * t * controlY1 + 3 * (1 - t) * t^2 * controlY2 + t^3 * endY
                    cel.position = Point(cel.position.x, newY)
                end
                --if changeXSize then
                --    local newWidth = startWidth + t * (endWidth - startWidth)
                --    cel.image:resize(newWidth,cel.image.height)
                --end
                --if changeYSize then
                --    local newHeight = startHeight + t * (endHeight - startHeight)
                --    cel.image:resize(cel.image.width,newHeight)
                --end
                        
            -- Move along straight line
            else
                if changeXPosition then
                    -- Calculate using linear interpolation
                    local newX = startX + t * (endX - startX)
                    -- Set new position for the cell
                    cel.position = Point(newX, cel.position.y)
                end
                if changeYPosition then
                    local newY = startY + t * (endY - startY)
                    cel.position = Point(cel.position.x, newY)
                end
                --if changeXSize then
                --    local newWidth = startWidth + t * (endWidth - startWidth)
                --    cel.image:resize(newWidth,cel.image.height)
                --end
                --if changeYSize then
                --    local newHeight = startHeight + t * (endHeight - startHeight)
                --    cel.image:resize(cel.image.width,newHeight)
                --end
            end
        
        end
        
        -- Add t of the last cel to bezierT
        table.insert(bezierT, 1)
    
        -- Set the last cel's position to the start cel's position when pingpong is selected
        if easingType == "pingpong" then
            if changeXPosition then
                maxFrameCel.position = Point(startX, maxFrameCel .position.y)
            end
            if changeYPosition then
                maxFrameCel.position = Point(maxFrameCel .position.x, startY)
            end
            --if changeXSize then
            --    maxFrameCel.image:resize(startWidth, maxFrameCel .image.height)
            --end
            --if changeYSize then
            --    maxFrameCel .image:resize(maxFrameCel .image.width, startHeight)
            --end
        end
        
        -- Refresh the app to reflect changes
        app.refresh()  
        
    end
    

    -- Trail function
    local function AddTrail(useBezier,changeXPosition, changeYPosition, controlX1, controlY1, controlX2, controlY2, numSteps, minOpacity, maxOpacity, minlength, maxlength)
        minlength = 0.1*minlength
        maxlength = 0.1*maxlength
        
        local startCel = minFrameCel 
        local endCel = maxFrameCel

        -- Begin and end of the whole movemment
        local startX, startY = startCel.position.x, startCel.position.y
        local endX, endY = endCel.position.x, endCel.position.y

        -- Calculate the max speed in the whole movement
        local maxSpeed = 0
        for i = 2, #cels do
            local currentCel = cels[i]
            local previousCel = cels[i - 1]
            local currentX, currentY = currentCel.position.x, currentCel.position.y
            local previousX, previousY = previousCel.position.x, previousCel.position.y
            -- Get speed of the current cel
            local distance = math.sqrt((currentX - previousX)^2 + (currentY - previousY)^2)
            -- Refresh the max speed 
            if distance > maxSpeed then
                maxSpeed = distance
            end
        end

        -- Create trail for each cel except for the first cel
        for i = minFrameNumber + 1 , minFrameNumber + #cels - 1 do  

            -- Get the current cel(trail target) and the previous cel
            local targetCel = nil
            local previousCel = nil
            for _, cel1 in ipairs(cels) do
                if cel1.frame.frameNumber == i then
                        targetCel = cel1
                    break
                end
            end
            for _, cel2 in ipairs(cels) do
                if cel2.frame.frameNumber == i-1 then
                    previousCel = cel2
                    break
                end
            end

            -- Get the position of the current cel
            local targetX, targetY = targetCel.position.x, targetCel.position.y
                        
            -- Use the image in the current cel as brush
            local brushImage = Image(targetCel.image)
                        
            -- Get the speed of the current cel
            local previousX, previousY = previousCel.position.x, previousCel.position.y
            local distance = math.sqrt((targetX - previousX)^2 + (targetY - previousY)^2)
                        
            -- Calculate the percentage of the current speed relative to the maximum speed
            -- The closer the current cel's speed is to the maximum speed, the closer the  trail length is to maxlength. 
            -- The closer the current cel's speed is to zero, the closer the trail length is to minlength.
            local lengthFactor = distance/maxSpeed
    
                    
           
                        
            
            -- Draw incrementally along the trail path, accumulating the brush image onto the same trailImage
            -- Create a new image for drawing all trail paths
            local trailImage = Image(sprite.width, sprite.height)
                    
                -- Get the starting position of the trail when the motion path is along a straight line
                local trailStartX = startX
                local trailStartY = startY
                if ((targetX-startX)/(endX-startX))-(minlength + (maxlength-minlength)*lengthFactor)>0 then
                    trailStartX = startX + (endX-startX)*(((targetX-startX)/(endX-startX))-(minlength + (maxlength-minlength)*lengthFactor))
                end
                if ((targetY-startY)/(endY-startY))-(minlength + (maxlength-minlength)*lengthFactor)>0 then
                    trailStartY = startY + (endY-startY)*(((targetY-startY)/(endY-startY))-(minlength + (maxlength-minlength)*lengthFactor))
                end
                -- Get the position of the trail image(on Bezier curve) when the motion path is along a Bezier curve.
                local bezierPoints = {}    
                if useBezier then
                    -- Get t of the starting and ending points of the trail
                    local tA
                    local tB = bezierT[i-minFrameNumber]
                    tA = tB-(minlength + (maxlength-minlength)*lengthFactor) 
                    if tA<0 then
                        tA=0
                    end
                    -- Uniform sampling between the starting and ending points of the trail
                    for i = 0, numSteps - 1 do
                        local t
                        if numSteps > 1 then
                            t = tA + (tB - tA) * (i / (numSteps)) 
                        else
                            t = tA
                        end
                            local point = bezier(t, startX, startY, controlX1, controlY1, controlX2, controlY2, endX, endY)
                            table.insert(bezierPoints, point)
                    end
                end
                            
                -- Draw each image in the trail		    
                for step = 0, numSteps - 1 do
                    -- Calculate the opacity of the current image (the closer to the end the more transparent it is)
                    local opacity = minOpacity + ((maxOpacity - minOpacity) * (step / numSteps))
                                    
                    -- Create a temporary copy of the brushImage and set the opacity
                    local fadedBrush = Image(brushImage.width, brushImage.height)
                    for y = 0, brushImage.height - 1 do
                        for x = 0, brushImage.width - 1 do
                        local pixelColor = brushImage:getPixel(x, y)
                                                
                            -- Get RGBA channel
                            local r = app.pixelColor.rgbaR(pixelColor)
                            local g = app.pixelColor.rgbaG(pixelColor)
                            local b = app.pixelColor.rgbaB(pixelColor)
                            local a = app.pixelColor.rgbaA(pixelColor)
                            
                            -- Adjust opacity
                            a = math.floor(a * (opacity / 255))
                            
                            -- Draw new pixel values to fadedBrush
                            fadedBrush:putPixel(x, y, app.pixelColor.rgba(r, g, b, a))
                        end
                    end
                            
                    -- Draw image with transparency to trailImage
                    -- When the motion path is along a bezier curve
                    if useBezier and changeXPosition and changeYPosition then
                        local posX = bezierPoints[step+1].x
                        local posY = bezierPoints[step+1].y
                        trailImage:drawImage(fadedBrush, posX, posY)
                    -- When the motion path is along a straight line
                    -- if motion path only along x axis or y axis, trail along a straight line
                    else
                        local stepX = (targetX - trailStartX) / numSteps
                        local stepY = (targetY - trailStartY) / numSteps
                        local posX = trailStartX+ step * stepX
                        local posY = trailStartY+ step * stepY
                        trailImage:drawImage(fadedBrush, posX, posY)
                    end
                end
                        
            
            
           
                        
                    
            -- Create a new cel to show the trail
            sprite:newCel(trailLayer, targetCel.frame.frameNumber, trailImage)
        end				

        -- Refresh the app to reflect changes
        app.refresh()  
    end


    -- Create a new layer for previewing the movement Bezier curve
    local previewLayer = sprite:newLayer()
    previewLayer.name = "Bezier Curve Preview"

    -- Create the main dialog 
        local dlg = Dialog{
            title = "Add Animation with Easing",
            -- Delete the preview layer when closing the dialog box
            onclose = function()
                if previewLayer then
                sprite:deleteLayer(previewLayer)  -- delete preview layer
                previewLayer = nil 
                end
                if clickApply == false then
                if trailLayer then
                    sprite:deleteLayer(trailLayer)
                    trailLayer=nil
                end
               
                cancelAnimation()
                end
                app.refresh()
            end
        }
        
    -- The range of movement for Bezier curve control points
    local sliderMaxValueX = sprite.width/2
    local sliderMaxValueY = sprite.height/2

    -- Start and end position of the Bezier curve
    local startX, startY = minFrameCel.position.x, minFrameCel.position.y
    local endX, endY = maxFrameCel.position.x, maxFrameCel.position.y

    -- Function for drawing points on the Bezier curve
    local function drawCircle(image, x, y, radius, color)
        for dx = -radius, radius do
            for dy = -radius, radius do
                if dx * dx + dy * dy <= radius * radius then
                    local px = x + dx
                    local py = y + dy
                    if px >= 0 and px < image.width and py >= 0 and py < image.height then
                        image:drawPixel(px, py, color)
                    end
                end
            end
        end
    end

    -- Update the Bezier curve preview
    local function updatePreview(controlX1, controlY1, controlX2, controlY2)
        -- Delete the current preview cel (if it exists)
        if previewLayer.cels[1] then
            for _, cel in ipairs(previewLayer.cels) do
                sprite:deleteCel(previewLayer, cel.frame.frameNumber)
            end
        end

        local image = Image(sprite.width, sprite.height)
        local numSteps = 100  -- Number of points; the higher the number, the smoother the curve

        -- Draw the Bezier curve
        for i = 0, numSteps do
            local t = i / numSteps
            -- Bezier curve formula
            local x = (1 - t)^3 * startX + 3 * (1 - t)^2 * t * controlX1 + 3 * (1 - t) * t^2 * controlX2 + t^3 * endX
            local y = (1 - t)^3 * startY + 3 * (1 - t)^2 * t * controlY1 + 3 * (1 - t) * t^2 * controlY2 + t^3 * endY
            image:drawPixel(x, y, Color{ r=255, g=0, b=0, a=100 })  -- Use red to draw path points
        end

        -- Draw control points
        local controlPointColor = Color{ r=0, g=255, b=0, a=100 }  -- Use green to draw control points
        local controlPointRadius = 2  -- Radius of the control points
        drawCircle(image, controlX1, controlY1, controlPointRadius, controlPointColor)  -- Draw control point 1
        drawCircle(image, controlX2, controlY2, controlPointRadius, controlPointColor)  -- Draw control point 2

        app.refresh()
        app.transaction(function()
            for i = minFrameNumber, maxFrameNumber do
                sprite:newCel(previewLayer,i, image)
            end
        end)
    end

    -- default control points
    local controlX1 = startX + (endX - startX) / 3 + (previousSettings.controlX1 or 0)
    local controlY1 = startY + (previousSettings.controlY1 or 0)
    local controlX2 = startX + 2 * (endX - startX) / 3 + (previousSettings.controlX2 or 0)
    local controlY2 = endY + (previousSettings.controlY2 or 0)

    -- Display the initial preview
    updatePreview(controlX1, controlY1, controlX2, controlY2)
    
    
    -- Pre-apply to preview the effect when adjusting any parameter 
    -- (the result will be canceled if the Apply button is not clicked when closing the dialog box)
    local function PreApply()
        animateCels(dlg.data.easingType, dlg.data.changeXPosition, dlg.data.changeYPosition, dlg.data.changeXSize, dlg.data.changeYSize,  (startX + (endX - startX) / 3 + dlg.data.controlX1 ), (startY + dlg.data.controlY1), (startX + 2 * (endX - startX) / 3 + dlg.data.controlX2 ), (endY + dlg.data.controlY2), dlg.data.useBezier)
        AddTrail(dlg.data.useBezier,  dlg.data.changeXPosition, dlg.data.changeYPosition,(startX + (endX - startX) / 3 + dlg.data.controlX1 ), (startY + dlg.data.controlY1), (startX + 2 * (endX - startX) / 3 + dlg.data.controlX2 ), (endY + dlg.data.controlY2), dlg.data.trailNumSteps , math.min(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.max(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.min(dlg.data.minTrailLength, dlg.data.maxTrailLength), math.max(dlg.data.minTrailLength, dlg.data.maxTrailLength) )
    end
    
    -- Adjustable parameters for the user
    dlg:separator{id= "Movement Path", text = "Movement Path"}

    -- check:changeXPosition
    dlg:check{ 
        id = "changeXPosition", 
        text = "Change X Position", 
        selected = previousSettings.changeXPosition or false ,
        onclick = function()
            if dlg.data.changeXPosition==false then
                cancelAnimation()
            end
            PreApply()
        end }

    -- check:changeYPosition
    dlg:check{ 
        id = "changeYPosition", 
        text = "Change Y Position", 
        selected = previousSettings.changeYPosition or false,
        onclick = function()
            if dlg.data.changeYPosition==false then
                cancelAnimation()
            end
            PreApply()
        end }

    dlg:newrow()

    -- check:use bezier
    dlg:check{
        id = "useBezier",
        text = "Use a Bézier Curve as Path",
        selected = previousSettings.useBezier or false, 
        onclick = function()
            dlg:modify{
            id = "controlPoint1",
            visible = dlg.data.useBezier
            }
            dlg:modify{
            id = "controlX1",
            visible = dlg.data.useBezier
            }
            dlg:modify{
            id = "controlY1",
            visible = dlg.data.useBezier
            }
            dlg:modify{
            id = "controlPoint2",
            visible = dlg.data.useBezier
            }
            dlg:modify{
            id = "controlX2",
            visible = dlg.data.useBezier
            }
            dlg:modify{
            id = "controlY2",
            visible = dlg.data.useBezier
            }
            PreApply()
        end
    }

    dlg:label{id = "controlPoint1", text = "Bézier Curve Control Point 1", visible = dlg.data.useBezier,}

    -- slider:controlX1
    dlg:slider{
        id = "controlX1",
        min = -sliderMaxValueX ,
        max = sliderMaxValueX ,  
        value = previousSettings.controlX1 or 0  ,
        visible = dlg.data.useBezier,
        onchange = function()
            local controlX1 = startX + (endX - startX) / 3 + dlg.data.controlX1
            local controlY1 = startY + dlg.data.controlY1
            local controlX2 = startX + 2 * (endX - startX) / 3 + dlg.data.controlX2
            local controlY2 = endY + dlg.data.controlY2
            updatePreview(controlX1, controlY1, controlX2, controlY2)
            PreApply()
        end
    }

    -- slider:controlY1
    dlg:slider{
        id = "controlY1",
        min = -sliderMaxValueY ,
        max = sliderMaxValueY ,  
        value = previousSettings.controlY1 or 0 ,
        visible = dlg.data.useBezier,
        onchange = function()
            local controlX1 = startX + (endX - startX) / 3 + dlg.data.controlX1
            local controlY1 = startY + dlg.data.controlY1
            local controlX2 = startX + 2 * (endX - startX) / 3 + dlg.data.controlX2
            local controlY2 = endY + dlg.data.controlY2
            updatePreview(controlX1, controlY1, controlX2, controlY2)
            PreApply()
        end
    }

    dlg:label{id = "controlPoint2", text = "Bézier Curve Control Point 2", visible = dlg.data.useBezier,}

    -- slider:controlX2
    dlg:slider{
        id = "controlX2",
        min = -sliderMaxValueX ,
        max = sliderMaxValueX ,  
        value = previousSettings.controlX2 or 0  ,
        visible = dlg.data.useBezier,
        onchange = function()
            local controlX1 = startX + (endX - startX) / 3 + dlg.data.controlX1
            local controlY1 = startY + dlg.data.controlY1
            local controlX2 = startX + 2 * (endX - startX) / 3 + dlg.data.controlX2
            local controlY2 = endY + dlg.data.controlY2
            updatePreview(controlX1, controlY1, controlX2, controlY2)
            PreApply()
        end
    }

    -- slider:controlY2
    dlg:slider{
        id = "controlY2",
        min = -sliderMaxValueY ,
        max = sliderMaxValueY ,  
        value = previousSettings.controlY2 or 0 ,
        visible = dlg.data.useBezier,
        onchange = function()
            local controlX1 = startX + (endX - startX) / 3 + dlg.data.controlX1
            local controlY1 = startY + dlg.data.controlY1
            local controlX2 = startX + 2 * (endX - startX) / 3 + dlg.data.controlX2
            local controlY2 = endY + dlg.data.controlY2
            updatePreview(controlX1, controlY1, controlX2, controlY2)
            PreApply()
        end
    }

    dlg:separator{id= "Movement Trail", text = "Movement Trail", tooltip = "Movement Trail will be created When both changeXPosition and changeYPosition are selected"}

    dlg:label{id = "trailSteps", text = "Trail Steps"}

    -- slider:trailNumSteps
    dlg:slider{
        id = "trailNumSteps",
        min = 0 ,
        max = 50,  
        value = previousSettings.trailNumSteps or 5  ,
        onchange = function()
            AddTrail(dlg.data.useBezier, dlg.data.changeXPosition, dlg.data.changeYPosition, (startX + (endX - startX) / 3 + dlg.data.controlX1 ), (startY + dlg.data.controlY1), (startX + 2 * (endX - startX) / 3 + dlg.data.controlX2 ), (endY + dlg.data.controlY2), dlg.data.trailNumSteps , math.min(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.max(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.min(dlg.data.minTrailLength, dlg.data.maxTrailLength), math.max(dlg.data.minTrailLength, dlg.data.maxTrailLength) )
        end
    }

    dlg:label{id = "rangeTrailOpacity", text = "Trail Opacity Range"}

    -- slider:minTrailOpacity
    dlg:slider{
        id = "minTrailOpacity",
        min = 0 ,
        max = 255,  
        value = previousSettings.minTrailOpacity or 0  ,
        onchange = function()
            AddTrail(dlg.data.useBezier, dlg.data.changeXPosition, dlg.data.changeYPosition, (startX + (endX - startX) / 3 + dlg.data.controlX1 ), (startY + dlg.data.controlY1), (startX + 2 * (endX - startX) / 3 + dlg.data.controlX2 ), (endY + dlg.data.controlY2), dlg.data.trailNumSteps , math.min(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.max(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.min(dlg.data.minTrailLength, dlg.data.maxTrailLength), math.max(dlg.data.minTrailLength, dlg.data.maxTrailLength) )
        end
    }

    -- slider:maxTrailOpacity
    dlg:slider{
        id = "maxTrailOpacity",
        min = 0 ,
        max = 255,  
        value = previousSettings.maxTrailOpacity or 255  ,
        onchange = function()
            AddTrail(dlg.data.useBezier, dlg.data.changeXPosition, dlg.data.changeYPosition, (startX + (endX - startX) / 3 + dlg.data.controlX1 ), (startY + dlg.data.controlY1), (startX + 2 * (endX - startX) / 3 + dlg.data.controlX2 ), (endY + dlg.data.controlY2), dlg.data.trailNumSteps , math.min(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.max(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.min(dlg.data.minTrailLength, dlg.data.maxTrailLength), math.max(dlg.data.minTrailLength, dlg.data.maxTrailLength) )
        end
    }

    dlg:label{id = "rangeTrailLength", text = "Trail Length Range"}

    -- slider:minTrailLength
    dlg:slider{
        id = "minTrailLength",
        min = 0 ,
        max = 10 ,  
        step = 1,
        value = previousSettings.minTrailLength or 0  ,
        onchange = function()
            AddTrail(dlg.data.useBezier,  dlg.data.changeXPosition, dlg.data.changeYPosition,(startX + (endX - startX) / 3 + dlg.data.controlX1 ), (startY + dlg.data.controlY1), (startX + 2 * (endX - startX) / 3 + dlg.data.controlX2 ), (endY + dlg.data.controlY2), dlg.data.trailNumSteps , math.min(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.max(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.min(dlg.data.minTrailLength, dlg.data.maxTrailLength), math.max(dlg.data.minTrailLength, dlg.data.maxTrailLength) )
        end
    }

    -- slider:maxTrailLength
    dlg:slider{
        id = "maxTrailLength",
        min = 0 ,
        max = 10 ,  
        step = 1,
        value = previousSettings.maxTrailLength or 2  ,
        onchange = function()
            AddTrail(dlg.data.useBezier, dlg.data.changeXPosition, dlg.data.changeYPosition, (startX + (endX - startX) / 3 + dlg.data.controlX1 ), (startY + dlg.data.controlY1), (startX + 2 * (endX - startX) / 3 + dlg.data.controlX2 ), (endY + dlg.data.controlY2), dlg.data.trailNumSteps , math.min(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.max(dlg.data.minTrailOpacity, dlg.data.maxTrailOpacity), math.min(dlg.data.minTrailLength, dlg.data.maxTrailLength), math.max(dlg.data.minTrailLength, dlg.data.maxTrailLength) )
        end
    }


    --dlg:separator{id= "Add Scaling Animation", text = "Add Scaling Animation"}

    -- check:changeXSize
    --dlg:check{
    --    id = "changeXSize", 
    --    text = "Change X Size", 
    --    selected = previousSettings.changeXSize or false ,
    --    onclick = function()
    --        if dlg.data.changeXSize == false then
    --            cancelAnimation()
    --        end
    --        PreApply()
    --    end
    --}

    -- check:changeYSize
    --dlg:check{
    --    id = "changeYSize",
    --    text = "Change Y Size",
    --    selected = previousSettings.changeYSize or false,
    --    onclick = function()	
    --        if dlg.data.changeYSize == false then
    --            cancelAnimation()
    --        end
    --        PreApply()
    --    end 
    --}

    dlg:separator{id= "Easing Type", text = "Easing Type"}

    -- Easing type combobox
    dlg:combobox{
        id = "easingType",
        options = easingTypes,
        selected = previousSettings.easingType or "linear",  -- Previous selected value
        onchange = function()
            local selected = dlg.data.easingType
            dlg:modify{id="curveDescription", text=easingDescriptions[selected]}
            PreApply()
        end
    }

    -- Curve description label
    dlg:label{
    id = "curveDescription",
    text = easingDescriptions[dlg.data.easingType] or easingDescriptions["linear"]
    }

    PreApply()

    dlg:newrow()

    -- Button:Apply
    dlg:button{
        id = "apply",
        text = "Apply",
        onclick = function()
        clickApply=true
        app.userData.dialogSettings = {
            easingType = dlg.data.easingType,
            useBezier = dlg.data.useBezier,
            changeXPosition = dlg.data.changeXPosition,
            changeYPosition = dlg.data.changeYPosition,
            changeXSize = dlg.data.changeXSize,
            changeYSize = dlg.data.changeYSize,
            controlX1 = dlg.data.controlX1,
            controlY1 = dlg.data.controlY1,
            controlX2 = dlg.data.controlX2,
            controlY2 = dlg.data.controlY2,
            trailNumSteps = dlg.data.trailNumSteps ,
            minTrailOpacity = dlg.data.minTrailOpacity ,
            maxTrailOpacity = dlg.data.maxTrailOpacity ,
            minTrailLength = dlg.data.minTrailLength ,
            maxTrailLength = dlg.data.maxTrailLength ,
        }
        PreApply()
        
        dlg:close()  -- Close the dialog after applying
        end
    }

    -- Show the dialog, allowing interaction with other UI elements
    dlg:show{wait = false}
  
end