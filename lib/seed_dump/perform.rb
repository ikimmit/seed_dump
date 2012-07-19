module SeedDump
  class Perform

    def initialize
      @opts = {}
      @ar_options = {} 
      @indent = ""
      @models = []
      @seed_rb = "" 
      @id_set_string = ""
      @verbose = true
      @model_dir = 'app/models/**/*.rb'
    end

    def setup(env)
      # config
      @opts['with_id'] = !env["WITH_ID"].nil?
      @opts['no-data'] = !env['NO_DATA'].nil?
      @opts['models']  = env['MODELS'] || (env['MODEL'] ? env['MODEL'] : "")
      @opts['file']    = env['FILE'] || "#{Rails.root}/db/seeds.rb"
      @opts['append']  = (!env['APPEND'].nil? && File.exists?(@opts['file']) )
      @ar_options      = env['LIMIT'].to_i > 0 ? { :limit => env['LIMIT'].to_i } : {}
      @indent          = " " * (env['INDENT'].nil? ? 2 : env['INDENT'].to_i)
      @opts['models']  = @opts['models'].split(',').collect {|x| x.underscore.singularize.camelize }
      @opts['schema']  = env['PG_SCHEMA']
    end

    def loadModels
      Dir[@model_dir].sort.each do |f|
        # parse file name and path leading up to file name and assume the path is a module
        f =~ /app\/models\/(.*).rb/
        # split path by /, camelize the constituents, and then reform as a formal class name
        model = $1.split("/").map {|x| x.camelize}.join("::")
        @models.push model if @opts['models'].include?(model) || @opts['models'].empty? 
      end
    end

    def dumpAttribute(a_s,r,k,v)
      v = attribute_for_inspect(r,k)
      if k == 'id' && @opts['with_id']
        @id_set_string = "{ |c| c.#{k} = #{v} }.save"
      else
        a_s.push("#{k.to_sym.inspect} => #{v}") unless k == 'id' && !@opts['with_id']
      end 
    end

    def dumpModel(model)
      @id_set_string = ''
      create_hash = ""
      rows = []
      arr = []
      arr = model.find(:all, @ar_options) unless @opts['no-data']
      arr = arr.empty? ? [model.new] : arr 
      arr.each_with_index { |r,i| 
        attr_s = [];
        r.attributes.each { |k,v| dumpAttribute(attr_s,r,k,v) }
        if @id_set_string.empty?
          rows.push "#{@indent}{ " << attr_s.join(', ') << " }"
        else
          create_hash << "\n#{model}.create" << '( ' << attr_s.join(', ') << ' )' << @id_set_string
        end
      } 
      if @id_set_string.empty?
        "\n#{model}.create([\n" << rows.join(",\n") << "\n])\n"
      else
        create_hash
      end
    end

    def dumpModels
      @seed_rb = ""
      @models.sort.each do |model|
          m = model.constantize
          if m.ancestors.include?(ActiveRecord::Base)
            puts "Adding #{model} seeds." if @verbose
            @seed_rb << dumpModel(m) << "\n\n"
          else
            puts "Skipping non-ActiveRecord model #{model}..." if @verbose
          end
      end
    end

    def writeFile
      File.open(@opts['file'], (@opts['append'] ? "a" : "w")) { |f|
        f << "# Autogenerated by the db:seed:dump task\n# Do not hesitate to tweak this to your needs\n" unless @opts['append']
        f << "#{@seed_rb}"
      }
    end

    #override the rails version of this function to NOT truncate strings
    def attribute_for_inspect(r,k)
      value = r.attributes[k]
      
      if value.is_a?(String) && value.length > 50
        "#{value}".inspect
      elsif value.is_a?(Date) || value.is_a?(Time)
        %("#{value.to_s(:db)}")
      else
        value.inspect
      end
    end

    def setSearchPath(path, append_public=true)
        path_parts = [path.to_s, ('public' if append_public)].compact
        ActiveRecord::Base.connection.schema_search_path = path_parts.join(',')
    end

    def run(env)

      setup env

      setSearchPath @opts['schema'] if @opts['schema']

      loadModels

      puts "Appending seeds to #{@opts['file']}." if @opts['append']
      dumpModels

      puts "Writing #{@opts['file']}."
      writeFile

      puts "Done."
    end
  end
end
