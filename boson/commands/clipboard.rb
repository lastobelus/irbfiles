module Clipboard
  def self.included(mod)
    require 'clipboard'
  end

  def clipboard_copy(stuff)
    ::Clipboard.write(stuff)
  end
  
  def clipboard_paste
    ::Clipboard.read
  end
end