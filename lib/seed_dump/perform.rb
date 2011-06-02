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
      @model_dir = 'app/models/*.rb'
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
      @opts['models']  = @opts['models'].split(',').collect {|x| x.underscore.singularize.camelize.constantize }
    end

    def loadModels
      Dir[@model_dir].sort.each do |f|
        model = File.basename(f, '.*').camelize.constantize
        @models.push model if @opts['models'].include?(model) || @opts['models'].empty? 
      end
    end

    def dumpAttribute(a_s,r,k,v)
      v = r.attribute_for_inspect(k)
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
          puts "Adding #{model} seeds." if @verbose
          @seed_rb << dumpModel(model) << "\n\n"
      end
    end

    def writeFile
      File.open(@opts['file'], (@opts['append'] ? "a" : "w")) { |f|
        f << "# Autogenerated by the db:seed:dump task\n# Do not hesitate to tweak this to your needs\n" unless @opts['append']
        f << "#{@seed_rb}"
      }
    end

    def run(env)

      setup env

      loadModels

      puts "Appending seeds to #{@opts['file']}." if @opts['append']
      dumpModels

      puts "Writing #{@opts['file']}."
      writeFile

      puts "Done."
    end
  end
end