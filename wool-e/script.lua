----[Some Constants for rendering stuff]----
local BorderFadingDistance = 5
local BlockMaxResolutionDistance= 10
local DarknessFadingDistance = 9
local DefaultFov = 90
local DefaultPPCM = 4

--Don't change this too much or something may break
local DefaultScreenHeight = 18
local DefaultScreenWidth = 36

---------[Ray generation]---------

local function rayDir(w, x,h, xfov)
    local yfov = h * xfov / w
    local xDeg = xfov / 2 - (xfov / (w - 1)) * (x - 1)
    --Using partial application to not perform unnessesary calculations later on
    return function (y)
        local yDeg = yfov / 2 - (yfov / (h - 1)) * (y - 1)
        return vectors.angleToDir(yDeg, xDeg)
    end
end

--adjusting ray position with the pixel density so they aren't coming from one point, mostly useful with Wacky FOVs
local function rayPos(x, y, ppcm)
    --partial application here doesn't bring much benefit due to how cheap the calculations are
    return vec(x / ppcm / 100, y / ppcm / 100 , 0)
end

--bakery
local function bakeRays(w, h, ppcm, fov)
    local rays = {}
    for x = 1, w do
        rays[x] = {}
        local yf = rayDir(w,x,h,fov)
        for y = 1, h do
                rays[x][y] = {
                rayPos(x - w / 2, y - h / 2, ppcm),
                yf(y)
            }
        end
    end
    return rays
end

-------------------------------------
local rays = bakeRays(DefaultScreenWidth,DefaultScreenHeight,DefaultPPCM,DefaultFov)

--Upper case table because string.upper() is too slow
local upper = {
    down="DOWN",
    up="UP",
    north="NORTH",
    south="SOUTH",
    west="WEST",
    east="EAST"
}

function getTexture(block,side)
    local blockTextures = block:getTextures()
    --If the block doesn't have a particle texture then it probably doesn't have other textures either
    if not blockTextures.PARTICLE then
        return textures["model.sky"]
    end
    local side = upper[side]

    --not full or special blocks may not have a side texture, but will have a particle texture most of the time
    if blockTextures[side] and #blockTextures[side] > 0 then
        return textures:fromVanilla("blank",blockTextures[side][1]..".png")
    else
        return textures:fromVanilla("blank",blockTextures.PARTICLE[1]..".png")
    end
end

--adjusting axies depending on the side and also tinting them differently so they don't look too flat
local axies = {
    up = {"x", "z", 1},
    down = {"x", "z", 0.5},
    north = {"x", "y", 0.9},
    south = {"x", "y", 0.9},
    west = {"z", "y", 0.7},
    east = {"z", "y", 0.7}
}

--get the texture coordinates of the exact pixel the raycast hit
local function getPixel(hitpos, side)
    --reduce the vector so we get local coordinates only
    hitpos:reduce(1, 1, 1)
    local xAxis, yAxis, tint = table.unpack(axies[side])
    --flip the coordinates because textures have different coordinate origin
    local x = 1 - hitpos[xAxis]
    local y = 1 - hitpos[yAxis]
    return x, y, tint
end

--Convert an rgb vector to greyscale with a green tint, which makes it greenscale probably
function toGrayScale(vector)
    local y = 0.299*vector.r+0.557*vector.g+0.144*vector.b
    local green = math.min(y*1.5,1)
    vector:set(y/1.5,green,y/1.5,vector.a)
end

--self explanatory
function isNearBorder(x,y,tolerance)
    return x < tolerance or x > 1-tolerance or y < tolerance or y > 1-tolerance
end
function render(tick,playerPos,playerRot,bfd,brd,wr,hr,dfd,mode)
    local turn = tick%2
    local turn2 = math.ceil(tick/2)%2
    --Splitting the raycast calculation between 4 frames, this particular pattern looks sick as hell
    for x = turn+1,#rays,2 do
        for y = turn2+1,#rays[x],2 do
            --rotating the rays so they face the same direction as the player, also angles from player:getRot() are inverted for some reason :/
            local rayStart = playerPos + vectors.rotateAroundAxis(-playerRot, rays[x][y][1], vec(0, 1, 0))
            local rayDir = vectors.rotateAroundAxis(-playerRot, rays[x][y][2], vec(0, 1, 0))
            local block, hitPos, side = raycast:block(rayStart, rayStart+rayDir*30,"OUTLINE")
            
            --getting the lightlevel from a block before the hit position so it's not just 0
            local lightLevel = world.getLightLevel(hitPos-rayDir)/15
            --increase the lightLevel if the night mode is on
            if mode == 2 then
                lightLevel = math.min(lightLevel+0.6,1)
            end

            local distance = (rayStart-hitPos):length()
            local tx,ty,tint = getPixel(hitPos,side) 

            --to avoid tinting the sky
            if block.id ~= "minecraft:air" then
                --tinting the borders a little so it's easier to distinguish blocks but also fading them with distance so there's not random dark pixels
                if isNearBorder(tx,ty,0.1) then
                    tint = tint * math.clamp(distance/bfd,0.9,1)
                end
                --also just tinting blocks the further they are in general, for better contrast between near and far objects
                tint = tint*math.clamp(dfd/distance,0.6,1)*math.min(lightLevel+0.6,1)
            else
                tint = 1
            end
            local texture = getTexture(block,side)
            --Shitty mip-mapping that just changes resolution
            local MipDistance = math.min(brd/distance,16)
            --Flipping the x and y because textures have different coordinate origin which pisses me off tbh
            local pixel = texture:getPixel(tx*MipDistance,ty*MipDistance):mul(tint,tint,tint,1)
            --turn on the green scale for the night vision mode, because ofc
            if mode == 2 then
            toGrayScale(pixel)
            end
            textures["model.textsure"]:setPixel(wr-x+1, hr-y+1, pixel)
        end
    end
    textures["model.textsure"]:update()
end
local tick = 1
function events.render()
    tick = tick + 1
    local playerPos = player:getPos()
    playerPos.y = player:getEyeY()
    local playerRot = player:getRot()[2]
    render(tick,playerPos,playerRot,BorderFadingDistance,BlockMaxResolutionDistance,DefaultScreenWidth,DefaultScreenHeight,DarknessFadingDistance)
end

function events.chat_send_message(msg)
    return msg
end
