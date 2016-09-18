class Trie
  attr_reader :root

  def initialize
    @root = Node.new
  end

  def add(word)
    node = @root
    word.chars { |ch|
      unless node.next[ch] then
        node.next[ch] = Node.new
      end
      node = node.next[ch]
    }
    node.endflg = true
  end
end

class Node
  attr_accessor :next, :parent, :endflg
  def initialize
    #(parent)
    # @now = char # 現在の文字
    @next = {}; # 次のノードへの参照
    #@parent = parent # 親ノード(上まで辿って文字列を復元する)
      @endflg = false;
  end

  def has_next?
    @next != {}
  end
end
