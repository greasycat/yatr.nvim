local LRU = {}
LRU.__index = LRU

function LRU.new(capacity)
    local self = setmetatable({
        capacity = capacity,
        size = 0,
        map = {},
        head = {},
        tail = {}
    }, LRU)
    self.head.next = self.tail
    self.tail.prev = self.head
    return self
end

function LRU:_remove(node)
    node.prev.next = node.next
    node.next.prev = node.prev
end

function LRU:_move_to_front(node)
    self:_remove(node)
    node.next = self.head.next
    node.prev = self.head
    self.head.next.prev = node
    self.head.next = node
end

function LRU:get(key)
    local node = self.map[key]
    if not node then return nil end
    self:_move_to_front(node)
    return node.value
end

function LRU:set(key, value)
    local node = self.map[key]
    if node then
        node.value = value
        self:_move_to_front(node)
    else
        if self.size >= self.capacity then
            local lru = self.tail.prev
            self.map[lru.key] = nil
            self:_remove(lru)
            self.size = self.size - 1
        end
        local new_node = {key = key, value = value, next = self.head.next, prev = self.head}
        self.head.next.prev = new_node
        self.head.next = new_node
        self.map[key] = new_node
        self.size = self.size + 1
    end
end

return LRU