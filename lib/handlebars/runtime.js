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

  evaluateProperty: function(context, data, parts, indirect) {
    if (parts === undefined || parts.length === 0) {
        return context;
    }

    // If the first part starts with a ~, use data as the effectiveContext
    var isData = parts[0][0] === '~';
    var effectiveContext = isData ? data : context;

    if (isData) {
        parts[0] = parts[0].slice(1);
    }

    for(var i=0, l=parts.length; i<l; i++) {
        var part = parts[i];

        // if (Object.prototype.toString.call(part) == '[object Array]') {
        //     // Handle indirect ID Lookup
        //     part = this.evaluateProperty(context, data, part);
        //     effectiveContext = this.evaluateProperty(effectiveContext, data, part.split('.'));
        // } else
        if (isData && part === '') {
            effectiveContext = data;
        } else {
            effectiveContext = Handlebars.VM.nameLookup(effectiveContext, part, context, data);
        }
    }

    return effectiveContext;
  },

  nameLookup: function(context, name, depth0, data) {
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
        toReturn = toReturn.call(context, depth0, data);
    }

    return toReturn;
  }
  
};

Handlebars.template = Handlebars.VM.template;

// END(BROWSER)

