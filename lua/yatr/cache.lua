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
    local prev_node = node.prev
    local next_node = node.next
    prev_node.next = next_node
    next_node.prev = prev_node
end

function LRU:_move_to_front(node)
    self:_remove(node)
    local head_next = self.head.next
    node.next = head_next
    node.prev = self.head
    head_next.prev = node
    self.head.next = node
end

function LRU:get(key)
    local node = self.map[key]
    if not node then
        return nil
    end
    self:_move_to_front(node)
    return node.value
end

function LRU:set(key, value)
    local node = self.map[key]
    if node then
        node.value = value
        self:_move_to_front(node)
        return
    end

    if self.size >= self.capacity then
        local lru = self.tail.prev
        self.map[lru.key] = nil
        self:_remove(lru)
        self.size = self.size - 1
    end

    local head_next = self.head.next
    local new_node = {
        key = key,
        value = value,
        next = head_next,
        prev = self.head
    }
    head_next.prev = new_node
    self.head.next = new_node
    self.map[key] = new_node
    self.size = self.size + 1
end

return LRU
