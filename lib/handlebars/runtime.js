var Handlebars = require("./base");

// BEGIN(BROWSER)
Handlebars.VM = {
  template: function(templateSpec) {
    // Just add water
    var container = {
      escapeExpression: Handlebars.Utils.escapeExpression,
      invokePartial: Handlebars.VM.invokePartial,
      programs: [],
      program: function(i, fn, data) {
        var programWrapper = this.programs[i];
        if(data) {
          return Handlebars.VM.program(fn, data);
        } else if(programWrapper) {
          return programWrapper;
        } else {
          programWrapper = this.programs[i] = Handlebars.VM.program(fn);
          return programWrapper;
        }
      },
      programWithDepth: Handlebars.VM.programWithDepth,
      noop: Handlebars.VM.noop
    };

    return function(context, options) {
      options = options || {};
      return templateSpec.call(container, Handlebars, context, options.helpers, options.partials, options.data);
    };
  },

  programWithDepth: function(fn, data, $depth) {
    var args = Array.prototype.slice.call(arguments, 2);

    return function(context, options) {
      options = options || {};

      return fn.apply(this, [context, options.data || data].concat(args));
    };
  },
  program: function(fn, data) {
    return function(context, options) {
      options = options || {};

      return fn(context, options.data || data);
    };
  },
  noop: function() { return ""; },
  invokePartial: function(partial, name, context, helpers, partials, data) {
    var options = { helpers: helpers, partials: partials, data: data };

    if(partial === undefined) {
      throw new Handlebars.Exception("The partial " + name + " could not be found");
    } else if(partial instanceof Function) {
      return partial(context, options);
    } else if (!Handlebars.compile) {
      throw new Handlebars.Exception("The partial " + name + " could not be compiled when running in runtime-only mode");
    } else {
      partials[name] = Handlebars.compile(partial, {data: data !== undefined});
      return partials[name](context, options);
    }
  },

  evaluateProperty: function(context, paths) {
    // recurse the context using the supplied paths
    for (var i = 0; i < paths.length; i++) {
        context = Handlebars.VM.nameLookup(context, paths[i]);
    }
    return context;
  },

  nameLookup: function(context, name) {
    var toReturn;

    // First, check the context directly
    if (context[name] !== undefined){
        toReturn = context[name];
    } else {

        // Does this look like a Backbone Model?
        if (context.get !== undefined && context.at === undefined) {
          toReturn = context.get(name);

        // Does this look like a Backbone Collection?
        } else if (context.at !== undefined && /^\d+$/.test(name)) {
          toReturn = context.at(name);

        } else {
          return undefined;
        }
    }

    // If toReturn is a method, then execute it.
    if (toReturn !== undefined && Object.prototype.toString.call(toReturn) === '[object Function]'){
        toReturn = toReturn.call(context);
    }

    return toReturn;
  }
  
};

Handlebars.template = Handlebars.VM.template;

// END(BROWSER)

