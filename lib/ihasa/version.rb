# encoding: utf-8

module Ihasa
  # This module holds the Ihasa version information.
  module Version
    STRING = '1.1.2'

    module_function

    def version(debug = false)
      STRING
    end
  end
end
