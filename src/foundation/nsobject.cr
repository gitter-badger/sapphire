module Sapphire
  abstract class NSObject
    macro objc_class
      def initialize(s : UInt8*)
        super(s)
      end
    end

    macro objc_method_arg(value, type)
      {% if type == "NSUInteger" %}
        {{value.id}}.to_nsuinteger
      {% elsif type == "BOOL" %}
        {{value.id}}
      {% elsif type == "SEL" %}
        {{value.id}}.to_sel
      {% elsif type == "NSString" %}
        {{value.id}}.to_nsstring
      {% elsif type == "const_char_ptr" %}
        {{value.id}}.cstr
      {% else %}
        {{value.id}}
      {% end %}
    end

    macro objc_init_method(method_name, crystal_method = nil)
      {{ "##{crystal_method ||= method_name}".id }}
      def self.{{crystal_method.id}}
        self.new(nsclass.send_msg({{method_name}}))
      end
    end

    macro objc_method_helper(receiver, method_name, args = nil, returnType = nil, crystal_method = nil)
      {{ "##{crystal_method ||= method_name}".id }}
      {{ "##{args ||= [] of Symbol}".id }}
      def {{crystal_method.id}}({% for i in 0 ... args.length %}{% if i > 0 %} , {% end %} {{"arg#{i}".id}} {%if args[i] != :id && args[i] != :NSUInteger %}{% if args[i] == :BOOL %}: Bool{% end %}{% if args[i] == :NSString %}: String|NSString {% end %}{% if args[i] == :SEL %}: Selector|String? {% end %}{% if args[i] == :const_char_ptr %}: String {% end %}{% end %}{% end %})
        
        res = Sapphire.send_msg({{receiver}}, {{method_name}}
          {% for i in 0 ... args.length %}
            , objc_method_arg({{"arg#{i}".id}}, {{args[i]}})
          {% end %}
        )

        {% if crystal_method == "initialize" %}
          @obj = res
        {% elsif returnType == "NSUInteger" %}
          res.address
        {% elsif returnType == "BOOL" %}
          res.address != 0
        {% elsif returnType == "unichar" %}
          res.address.chr
        {% elsif returnType == "void" || returnType == nil %}
          self
        {% elsif returnType == "id" %}
          klass = NSClass.new(LibObjC.objc_msgSend(res, "class".to_sel.to_objc) as LibObjC::Class)
          if klass.name == "__NSCFString"
            NSString.new(res)
          elsif klass.name == "NSButton"
            NSButton.new(res)
          elsif klass.name == "NSTextField"
            NSTextField.new(res)
          else
            res
          end
        {% else %}
          {{returnType.id}}.new(res)
        {% end %}
      end
    end

    macro objc_method(method_name, args = nil, returnType = nil, crystal_method = nil)
      {% if crystal_method == "initialize" %}
        objc_method_helper(nsclass.send_msg("alloc"), {{method_name}}, {{args}}, {{returnType}}, {{crystal_method}})
      {% else %}
        objc_method_helper(self.to_objc, {{method_name}}, {{args}}, {{returnType}}, {{crystal_method}})
      {% end %}
    end

    macro objc_static_method(method_name, args = nil, returnType = nil, crystal_method = nil)
      {{ "##{crystal_method ||= method_name}".id }}
      objc_method_helper(nsclass.obj as Pointer(UInt8), {{method_name}}, {{args}}, {{returnType}}, {{"self.#{crystal_method.id}"}})
    end

    macro import_class(objc_class_name = nil)
      def self.nsclass
        class_name = begin
          {% if objc_class_name %}
            {{objc_class_name}}
          {% else %}
            self.to_s["Sapphire::".length..-1]
          {% end %}
        end
        NSClass.new(class_name)
      end
    end

    macro export_class(objc_class_name = nil)
      $_{{@type.name.id}}_classPair = LibObjC.objc_allocateClassPair({{@type.superclass}}.nsclass.obj, {{@type.name.id}}.nsclass.obj as Pointer(UInt8), 0_u32)
      LibObjC.objc_registerClassPair($_{{@type.name.id}}_classPair)
      $x_{{@type.name.id}}_assoc_key = "crystal_obj"

      def self.nsclass
        NSClass.new $_{{@type.name.id}}_classPair
      end


      def initialize
        initialize(Sapphire.send_msg(nsclass.send_msg("alloc"), "init"))
        LibObjC.objc_setAssociatedObject(to_objc, $x_{{@type.name.id}}_assoc_key, Pointer(UInt8).new(self.object_id), LibObjC::AssociationPolicy::ASSIGN)
      end
    end

    macro export(method_name, selector = nil, types_encoding = nil)
      {{ "##{selector ||= method_name}".id }}
      {{ "##{types_encoding ||= "v@:"}".id }}
      $x_{{@type.name.id}}_{{method_name.id}}_imp = ->(obj : UInt8*, _cmd : LibObjC::SEL {%for t,i in types_encoding[3..-1].chars%}{{", a#{i} : UInt8*".id}}{%end%}) {
        ptr = LibObjC.objc_getAssociatedObject(obj, $x_{{@type.name.id}}_assoc_key)
        if ptr.nil?
          crystal_obj = {{@type.name.id}}.new(obj)
          LibObjC.objc_setAssociatedObject(obj, $x_{{@type.name.id}}_assoc_key, Pointer(UInt8).new(crystal_obj.object_id), LibObjC::AssociationPolicy::ASSIGN)
        else
          crystal_obj = ptr as {{@type.name.id}}
        end
        crystal_obj.{{method_name.id}}({%for t,i in types_encoding[3..-1].chars%}{%if i > 0%}{{",".id}}{%end%}{{"a#{i}".id}}{%end%})
      }
      LibObjC.class_addMethod($_{{@type.name.id}}_classPair, {{selector.stringify}}.to_sel.to_objc, $x_{{@type.name.id}}_{{method_name.id}}_imp.pointer as LibObjC::IMP, {{types_encoding}})
    end

    macro objc(code)
      {{ run "../support/export_method", @type.name, code }}
    end

    import_class

    def nsclass
      self.class.nsclass
    end

    def initialize(pointer : UInt8*)
      @obj = pointer
      retain
    end

    macro inherited
      objc_class
    end

    def to_objc
      @obj
    end

    def ==(other : NSObject)
      @obj == other.to_objc
    end

    def finalize
      release
    end

    objc_method "retain"
    objc_method "release"

    objc_method "performSelectorOnMainThread:withObject:waitUntilDone:", ["SEL", "id", "BOOL"], "void", "perform_selector_on_main_thread_with_object_wait_until_done"
  end
end