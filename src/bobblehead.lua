local imgui = require 'mimgui'
local ffi   = require('ffi')
local hook  = require('monethook')
local mem   = require('SAMemory')

mem.require('CPed')

local cast = ffi.cast
local gta  = ffi.load('GTASA')
local new  = imgui.new

ffi.cdef[[
    typedef struct { float x, y, z; } RwV3d;

    typedef struct {
        RwV3d    right; 
        uint32_t flags;
        RwV3d    up;
        uint32_t pad1;
        RwV3d    at;
        uint32_t pad2;
        RwV3d    pos;
        uint32_t pad3;
    } RwMatrix;

    typedef struct {
        int32_t  nodeID;
        int32_t  index;
        int32_t  flags;
        void*    pFrame;
    } RpHAnimNodeInfo;

    typedef struct {
        int32_t          flags;
        int32_t          numNodes;
        RwMatrix*        pMatrixArray;
        void*            pMatrixArrayUnaligned;
        RpHAnimNodeInfo* pNodeInfo;
        void*            pAnimTree;
        int32_t          currentAnim;
        float            timeStamp;
    } RpHAnimHierarchy;

    void* _Z13FindPlayerPedi(int index);
    void* RpSkinGeometryGetSkin(void* geometry);
    void* RpSkinAtomicGetHAnimHierarchy(void* atomic);
    void  _Z20RpClumpForAllAtomicsP7RpClumpPFP8RpAtomicS2_PvES3_(RpClump* clump, void*(*cb)(void*, void*), void* data);
    void  _ZN4CPed6RenderEv(CPed* ped);
]]

local HEAD_BONE          = 5
local SUB_BONES          = { 6, 7, 8 }
local OFFSET_ATOMIC_GEOM = 0x10

local outHier    = ffi.new('void*[1]')
local outSkinned = ffi.new('void*[1]')

local SW, SH    = getScreenResolution()
local ImguiState  = new.bool(false)
local enabled   = new.bool(false)
local sliderVal = new.int(3)

local function getIndex(hier, id)
    for i = 0, hier.numNodes - 1 do
        if hier.pNodeInfo[i].nodeID == id then return i end
    end
    return -1
end

local function matScale(mat, s)
    mat.right.x = mat.right.x * s; mat.right.y = mat.right.y * s; mat.right.z = mat.right.z * s
    mat.up.x    = mat.up.x    * s; mat.up.y    = mat.up.y    * s; mat.up.z    = mat.up.z    * s
    mat.at.x    = mat.at.x    * s; mat.at.y    = mat.at.y    * s; mat.at.z    = mat.at.z    * s
end

local function matTranslate(mat, tx, ty, tz)
    mat.pos.x = mat.pos.x + tx
    mat.pos.y = mat.pos.y + ty
    mat.pos.z = mat.pos.z + tz
end

local cbFindHier = ffi.cast('void*(*)(void*, void*)', function(atomic_ptr, _)
    local geomPtr = cast('void**', cast('uintptr_t', atomic_ptr) + OFFSET_ATOMIC_GEOM)[0]
    if geomPtr == nil then return atomic_ptr end
    if gta.RpSkinGeometryGetSkin(geomPtr) == nil then return atomic_ptr end
    outSkinned[0] = atomic_ptr
    outHier[0]    = gta.RpSkinAtomicGetHAnimHierarchy(atomic_ptr)
    return nil
end)

local function processBobbleHead(ped)
    if not enabled[0] then return end

    local clump = cast('CEntity*', ped).pRwClump
    if clump == nil then return end

    outSkinned[0] = nil
    outHier[0]    = nil
    gta._Z20RpClumpForAllAtomicsP7RpClumpPFP8RpAtomicS2_PvES3_(clump, cbFindHier, nil)

    if outSkinned[0] == nil or outHier[0] == nil then return end
    local hier = cast('RpHAnimHierarchy*', outHier[0])
    if hier == nil or hier.pMatrixArray == nil or hier.pNodeInfo == nil then return end

    local scale = sliderVal[0]

    for _, boneID in ipairs(SUB_BONES) do
        local idx = getIndex(hier, boneID)
        if idx >= 0 then
            local mat = hier.pMatrixArray + idx
            matScale(mat, scale)
            local tx, ty = 0.0, -(scale / 6.0) / 10.0
            if boneID == 8 then
                tx = ((scale / 8.0) / 10.0) / 8.0
                ty = ty / 8.0
            end
            matTranslate(mat, tx, ty, 0.0)
        end
    end

    local idx = getIndex(hier, HEAD_BONE)
    if idx >= 0 then matScale(hier.pMatrixArray + idx, scale) end
end

local pedRenderHook
pedRenderHook = hook.new(
    'void(*)(CPed*)',
    function(ped)
        local playerPed = gta._Z13FindPlayerPedi(0)
        if playerPed ~= nil and cast('uintptr_t', ped) == cast('uintptr_t', playerPed) then
            processBobbleHead(ped)
        end
        pedRenderHook(ped)
    end,
    cast('uintptr_t', cast('void*', gta._ZN4CPed6RenderEv))
)

imgui.OnFrame(
    function() return ImguiState[0] end,
    function()
        imgui.SetNextWindowPos(imgui.ImVec2(SW / 2, SH / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.Begin('BobbleHead', ImguiState, imgui.WindowFlags.NoCollapse)
        imgui.Checkbox('Enable', enabled)
        imgui.PushItemWidth(imgui.GetContentRegionAvail().x)
        imgui.SliderInt('##scale', sliderVal, 1, 10, 'Size: %d')
        imgui.PopItemWidth()
        imgui.End()
    end
)

function main()
    sampRegisterChatCommand('bobblehead', function()
        ImguiState[0] = not ImguiState[0]
    end)
    while true do wait(0) end
end
