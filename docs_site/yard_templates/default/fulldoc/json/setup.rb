# frozen_string_literal: true

require "json"

include Helpers::ModuleHelper

def init
  options.objects = objects = run_verifier(options.objects)
  options.delete(:objects)
  options.delete(:files)
  options.serializer.extension = "json"

  objects.each do |object|
    next if object.name == :root
    next if api_private?(object)

    begin
      Templates::Engine.with_serializer(object, options.serializer) { serialize(object) }
    rescue => e
      path = options.serializer.serialized_path(object)
      log.error "Exception occurred while generating '#{path}'"
      log.backtrace(e)
    end
  end
end

def serialize(object)
  # Check for @official tag (URL to official Tcl/Tk docs)
  official_tag = object.tags.find { |t| t.tag_name == "official" }
  official_url = official_tag&.text

  data = {
    name: object.name.to_s,
    path: object.path,
    type: object.type.to_s,
    title: format_object_title(object),
    docstring: object.docstring.to_s,
    tags: serialize_tags(object.tags, object),
    official_url: official_url,
  }.compact

  # Inheritance
  if object.is_a?(YARD::CodeObjects::ClassObject) && object.superclass
    data[:superclass] = object.superclass.to_s
  end

  # Mixins
  [:class, :instance].each do |scope|
    mixins = run_verifier(object.mixins(scope))
    if mixins.any?
      data[:"#{scope}_mixins"] = mixins.map { |m| m.path }
    end
  end

  # Class methods
  class_methods = public_class_methods(object)
  if class_methods.any?
    data[:class_methods] = class_methods.map { |m| serialize_method(m, object) }
  end

  # Instance methods
  instance_methods = public_instance_methods(object)
  if instance_methods.any?
    data[:instance_methods] = instance_methods.map { |m| serialize_method(m, object) }
  end

  # Attributes
  attrs = attr_listing(object)
  if attrs.any?
    data[:attributes] = attrs.map { |a| serialize_attribute(a, object) }
  end

  # Inherited/included methods
  inherited = inherited_methods(object)
  if inherited.any?
    data[:inherited_methods] = inherited
  end

  JSON.pretty_generate(data)
end

def serialize_method(method, parent_object)
  source = method.source rescue nil
  source_lines = source ? source.lines.count : nil

  {
    name: method.name.to_s,
    signature: method_signature(method),
    scope: method.scope.to_s,
    group: method.group,
    docstring: method.docstring.to_s,
    tags: serialize_tags(method.tags, parent_object),
    parameters: method.parameters.map { |p| { name: p[0].to_s, default: p[1] } },
    has_content: !method.docstring.empty? || method.tags.any?,
    source_file: method.file,
    source_line: method.line,
    source_lines: source_lines,
    source: source
  }
end

def serialize_attribute(attr, parent_object)
  {
    name: attr.name.to_s,
    reader: attr.reader?,
    writer: attr.writer?,
    docstring: attr.docstring.to_s,
    tags: serialize_tags(attr.tags, parent_object),
    has_content: !attr.docstring.empty? || attr.tags.any?
  }
end

def serialize_tags(tags, context_object)
  regular = []
  params = []
  returns = []
  options = []
  examples = []
  see_also = []
  official_docs_url = nil
  official_docs_text = nil

  tags.each do |tag|
    case tag.tag_name
    when "param"
      params << {
        name: tag.name,
        types: tag.types,
        text: tag.text
      }
    when "return"
      returns << {
        types: tag.types,
        text: tag.text
      }
    when "example"
      examples << {
        title: tag.name,
        code: tag.text
      }
    when "see"
      see_tag = serialize_see_tag(tag, context_object)
      next unless see_tag

      # Extract official Tcl/Tk docs to separate field
      if see_tag[:type] == "official_docs"
        official_docs_url = see_tag[:url]
        official_docs_text = see_tag[:text]
      else
        see_also << see_tag
      end
    when "option"
      opt = tag.pair
      options << {
        name: opt.name,
        types: opt.types,
        text: opt.text
      }
    else
      regular << {
        tag: tag.tag_name,
        name: tag.name,
        types: tag.types,
        text: tag.text
      }
    end
  end

  result = {}
  result[:regular] = regular if regular.any?
  result[:params] = params if params.any?
  result[:returns] = returns if returns.any?
  result[:options] = options if options.any?
  result[:examples] = examples if examples.any?
  result[:see_also] = see_also if see_also.any?
  if official_docs_url
    result[:official_docs_url] = official_docs_url
    result[:official_docs_text] = official_docs_text if official_docs_text
  end
  result
end

def serialize_see_tag(tag, context_object)
  ref = tag.name || tag.text
  return nil if ref.nil? || ref.empty?

  context_name = context_object.name.to_s
  context_path = context_object.path

  if ref =~ /\Ahttps?:\/\//
    # Check if official Tcl/Tk docs
    if ref.include?('tcl.tk') || ref.include?('tcl-lang.org')
      { type: "official_docs", url: ref, text: tag.text }
    else
      { type: "url", url: ref, text: tag.text }
    end
  elsif ref.start_with?('#')
    # #method_name -> instance method on same page
    { type: "instance_method", ref: ref, text: tag.text }
  elsif ref.start_with?('.')
    # .method_name -> class method on same page
    { type: "class_method", ref: ref, text: tag.text }
  elsif ref =~ /\A([A-Z]\w*)\.(\w+)\z/
    # ClassName.method - check if ClassName matches current context
    class_name, method_name = $1, $2
    if class_name == context_name || "#{context_path}".end_with?("::#{class_name}") || context_path == class_name
      # Same class - in-page class method
      { type: "class_method", ref: ".#{method_name}", text: tag.text }
    else
      { type: "external_class_method", ref: ref, class_name: class_name, method_name: method_name, text: tag.text }
    end
  elsif ref =~ /\A([A-Z][\w:]*)\#(\w+)\z/
    # ClassName#method - check if ClassName matches current context
    class_name, method_name = $1, $2
    if class_name == context_name || context_path.end_with?("::#{class_name}") || context_path == class_name
      # Same class - in-page instance method
      { type: "instance_method", ref: "##{method_name}", text: tag.text }
    else
      { type: "external_method", ref: ref, text: tag.text }
    end
  else
    { type: "reference", ref: ref, text: tag.text }
  end
end

def method_signature(method)
  params = method.parameters.map do |p|
    if p[1]
      "#{p[0]} #{p[1]}"
    else
      p[0].to_s
    end
  end.join(", ")

  if params.empty?
    method.name.to_s
  else
    "#{method.name}(#{params})"
  end
end

def public_method_list(object)
  # Filter to only methods defined directly in this object's namespace
  # (not from extended/included modules)
  prune_method_listing(
    object.meths(inherited: false, included: false, visibility: [:public]),
    included: false
  ).select { |m| m.namespace == object }.sort_by { |m| m.name.to_s }
end

def public_class_methods(object)
  public_method_list(object).select { |o| o.scope == :class }
end

def public_instance_methods(object)
  public_method_list(object).select { |o| o.scope == :instance }
end

# Get inherited/included methods grouped by source
def inherited_methods(object)
  inherited = {}

  # Get all public methods including inherited
  all_meths = object.meths(inherited: true, included: true, visibility: [:public])

  # Get methods defined directly on this object
  direct = public_method_list(object).map(&:name)

  all_meths.each do |m|
    next if direct.include?(m.name)
    next if m.namespace == object
    next unless m.namespace

    source = m.namespace.path
    inherited[source] ||= { class_methods: [], instance_methods: [] }

    if m.scope == :class
      inherited[source][:class_methods] << m.name.to_s
    else
      inherited[source][:instance_methods] << m.name.to_s
    end
  end

  # Sort method names and convert to final format
  inherited.transform_values do |v|
    v[:class_methods].sort!
    v[:instance_methods].sort!
    v
  end
end

def attr_listing(object)
  attrs = []
  object.inheritance_tree(true).each do |superclass|
    next if superclass.is_a?(YARD::CodeObjects::Proxy)
    next if !options.embed_mixins.empty? && !options.embed_mixins_match?(superclass)
    %i[class instance].each do |scope|
      superclass.attributes[scope].each do |_name, rw|
        attr = prune_method_listing([rw[:read], rw[:write]].compact, false).first
        attrs << attr if attr
      end
    end
    break if options.embed_mixins.empty?
  end
  attrs.sort_by { |o| [o.scope.to_s, o.name.to_s.downcase] }
end

# Check if object has @api private tag
def api_private?(object)
  object.tags.any? { |t| t.tag_name == "api" && t.text == "private" }
end
