define(['contrib/jquery'], function($) {
    BaseEntity.prototype = new Object;
    BaseEntity.prototype.constructor = BaseEntity;
    function BaseEntity(world) {
      this.world = world;
      this.updaters = [];
    }

    BaseEntity.prototype.addUpdater = function(callback, sequence) {
      sequence = (typeof sequence == 'undefined') ? 0 : sequence;
      callback.sequence = sequence;
      this.updaters.push(callback);
      this.updaters.sort(function(a,b) {
        return a.sequence - b.sequence
      });
    }



    BaseEntity.prototype.update = function(interp) {
        for (var i = 0; i < this.updaters.length; i++) {
            var returned = this.updaters[i].call(this, interp);
            if (returned != undefined) {
                // If this function returns ANYTHING, remove it from the updaters 
                this.updaters.splice(i,1);
            }
        }
    }

    // Good old fashioned linear interpolation
    function lerp(a, b, f) {
        return (a + f * (b - a));
    }

    // This function makes sure that all keys that are present in dictOne
    // are present in dictTwo, and vice versa.
    function unifyDictionaries(dictOne, dictTwo) {
        for (var key in dictOne) {
            if (dictTwo[key] == undefined)
                dictTwo[key] = dictOne[key];
        }
        for (var key in dictTwo) {
            if (dictOne[key] == undefined)
                dictOne[key] = dictTwo[key];
        }
    }

    // Compares to dictionaries by value to see if they
    // are equal. True if they are, false if they are not.
    // Assumes the dictionaries have the same keys.
    function compareDictionaries(dictOne, dictTwo) {
        for (var key in dictOne) {
            if (dictOne[key] != dictTwo[key])
                return false;
        }
        return true;
    }

    // This function compares a state dict (and what it defines)
    // with an object to see the common ground between the two. It
    // then returns a dictionary that matches the given state dictionary
    // with the objects current state. 
    //
    // e.g. an object with rotate, tilt and alpha pass in with a stateDict
    // of (rotate, tilt, color) will return a currentDict of (rotate, tilt,
    function buildStateDictionary(object, stateDict) {
        var currentStateDict = {};
        for (var key in stateDict) {
            if (key != 'constructor' && object[key] != undefined) {
                currentStateDict[key] = object[key];
            }
        }
        return currentStateDict;
    }

    // Interpolate this object from the startState to the endState, starting at startTime and
    // linearly interpolating until we get to endTime. Then the created updater will be removed
    // from the list of updaters.
    BaseEntity.prototype.tween = function(startState, endState, startTime, endTime) {
        var context = this;

        // Set the circle to it's given start state
        if (startState != undefined) {
            for (var key in startState) {
                if (context[key] != undefined) {
                    context[key] = startState[key];
                }
            }
        } else {
            // If we weren't passed a start state, just use the current one.
            startState = buildStateDictionary(context, endState);
        }
        unifyDictionaries(startState, endState);
        
        if (startTime == undefined) {
            // If startTime wasn't defined, use now.
            startTime = (new Date()).getTime(); 
        }

        var totalTimeTaken = endTime - startTime;
        var tweenUpdater = function(interp) {
            var now = (new Date()).getTime();
            var percent = (now - startTime)/(endTime - startTime); 
            if (percent > 1) percent = 1;
        if (percent < 0) percent = 0;
            
            // Make sure we should start, or have started
            if (now >= startTime) {
                // Lets do some lerping
                for (var key in context) {
                    if (startState[key] != undefined && endState[key] != undefined) {
                        context[key] = lerp(startState[key], endState[key], percent);
                    }
                }
                // Is it time to stop?
                var currentState = buildStateDictionary(context, startState);
                if (percent >= 1.0) { 
                    // If we don't return undefined, the updater manager removes us 
                    return false; 
                }
            }
        };
        this.addUpdater(tweenUpdater);
    }
    BaseEntity.prototype.removeAllUpdaters = function() {
        this.updaters = [];
    }
    World.prototype = new Object;
    World.prototype.constructor = World;
    function World(canvas) {
      this.objects = new Array();
      this.width = 320;
      this.height = 240;
      this.frametimes = new Array();
      this.ticks = 30;
      this.objects = new Array();
      this.color = "rgb(0,0,0)";
      this.displayFPS = false;
      // Number of times to update objects
      this.ticks = 30;

      this.setCanvas(canvas);
      //window.addEventListener('resize', this.properlyScopedEventHandler(this.eventResize), false);
    }

    World.prototype.properlyScopedEventHandler = function(f) {
      var scope = this;
      return function(evt) { f.call(scope, evt) }
    }

    World.prototype.setWidth = function(w) { this.width = w; }
    World.prototype.setHeight = function(h) { this.height = h; }

    World.prototype.setCanvas = function(canvas) {
      this.canvas = canvas;
      this.context = canvas.getContext('2d');
      //this.eventResize();
      this.setWidth(parseInt(canvas.getAttribute('width')));
      this.setHeight(parseInt(canvas.getAttribute('height')));
    }

    World.prototype.eventResize = function() {
      this.canvas.width = document.body.clientWidth;
      this.canvas.height = document.body.clientHeight;
      this.setWidth(document.body.clientWidth);
      this.setHeight(document.body.clientHeight);
    }

    World.prototype.addObject = function(object) {
      this.objects.push(object);
    }

    World.prototype.draw = function() {
      var c = this.context;

      c.save();
      c.fillStyle = this.color;
      c.fillRect(0, 0, this.width, this.height);
      c.restore();

      for (var i in this.objects) {this.objects[i].draw(c)}

      if (this.displayFPS) { this.drawFPS(); }
    }

    World.prototype.update = function() {
      for (var i in this.objects) {this.updateObject(this.objects[i])}
    }

    World.prototype.updateObject = function(object) {
      object.update()
    }

    World.prototype.drawFPS = function() {
      this.frametimes.push((new Date()).getTime());
      if (this.frametimes.length > 10) {this.frametimes.shift()}
      //milleseconds per frame
      var mspf = (this.frametimes[this.frametimes.length - 1] -
                  this.frametimes[0]) / this.frametimes.length;
      var fps = parseInt(1 / mspf * 1000);
      this.context.fillStyle = "rgb(255,255,255)";
      this.context.strokeStyle = "rgb(0,0,0)";
      this.context.font = "2em Arial";
      this.context.textBaseline = "bottom";
      this.context.fillText('FPS: ' + fps, 75, this.height);
      this.context.strokeText('FPS: ' + fps, 75, this.height);
    }

    //window.requestAnimFrame = function(callback) { window.setTimeout(callback, 1000 / 60) };
    window.requestAnimFrame = (function(){
      return  window.requestAnimationFrame       ||
              window.webkitRequestAnimationFrame ||
              window.mozRequestAnimationFrame    ||
              window.oRequestAnimationFrame      ||
              window.msRequestAnimationFrame     ||
              function(callback, element) {
                window.setTimeout(callback, 1000 / 60);
              };
    })();

    World.prototype.run = function(scope) {
      scope = typeof(scope) != 'undefined' ? scope : this;

      this.draw();
      this.update();

      requestAnimFrame(function() {scope.run.call(scope, scope)});
    }

    return {
        BaseEntity: BaseEntity,
        World: World
    }
});
