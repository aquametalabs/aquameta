define(['contrib/jquery', 'sphere/world'], function($, wrld) {
    var World = wrld.World;
    var BaseEntity = wrld.BaseEntity;

    function Sphere(canvas, x, y, radius) {
      World.prototype.constructor.call(this, canvas);
      this.x = x;
      this.y = y;
      this.radius = radius;
      this.circles = [];
      this.line_color = "rgb(255,255,255)";
      this.fill_color = "rgb(255,255,255)";
      this.fill_color = "rgb(0,0,0)";
    }
    Sphere.prototype.__proto__ = World.prototype;

    Sphere.prototype.draw = function(context) {
      World.prototype.draw.call(this, context);
      return;
      context.save();
      context.strokeStyle = this.line_color;
      context.fillStyle = this.fill_color;
      context.beginPath();
      context.arc(this.x, this.y, this.radius, 0, Math.PI * 2, true);
      context.fill();
      context.restore();
    }

    Sphere.prototype.toggleCircles = function() {
        var context = this;
        $(this.circles).each(function (index) {
          context.circles[index].is_active = !context.circles[index].is_active;
        });
    }

    Sphere.prototype.deactivateCircles = function() {
        var context = this;
        $(this.circles).each(function (index) {
          context.circles[index].is_active = false;
        });
    }

    Sphere.prototype.activateCircles = function() {
        var context = this;
        $(this.circles).each(function (index) {
          context.circles[index].is_active = true;
        });
    }

    Sphere.prototype.addCircle = function(circle) {
      World.prototype.addObject.call(this, circle);

      circle.beat_position = this.objects.indexOf(circle);

      var beat_time = 6/7 * 2000;

      this.circles.push(circle);
      //circle.addUpdater(function(interp) {
      //  var gray = 175;
      //  if (this.is_active) {
      //    var now = new Date().getTime();
      //    var num = this.sphere.objects.length;
      //    var measure_time = beat_time * num;

      //    var current_measure_time = now % measure_time;
      //    var current_beat = current_measure_time / beat_time;


      //    var STEP_GRANULARITY = 0.95;
      //    if (!this.has_mouse) { 
      //      if (Math.abs(this.beat_position - current_beat) < 1) {
      //        this.alpha = Math.sin( (current_beat - this.beat_position) * (Math.PI / 2) + (Math.PI / 2) )
      //      } else if (Math.abs(this.beat_position + num - current_beat) < 1) {
      //        this.alpha = Math.sin( (current_beat - this.beat_position - num) * (Math.PI / 2) + (Math.PI / 2) )
      //      } else {
      //        this.alpha = 0;
      //      }
      //    } else {
      //      this.alpha = 1;
      //      this.rotation_velocity *= STEP_GRANULARITY;
      //      if (Math.abs(this.rotation_velocity) < 0.005) {
      //          this.rotation_velocity = 0.0;
      //      }
      //    }

      //    var lerped_color = "rgb("+lerp(gray, this.color_int[0], this.alpha)+", "+
      //                              lerp(gray, this.color_int[1], this.alpha)+", "+
      //                              lerp(gray, this.color_int[2], this.alpha)+")";

      //    $(this.my_div).find("a").css("color", lerped_color); 
      //  } else {
      //    $(this.my_div).find("a").css("color", "rgb("+gray+", "+gray+", "+gray+")"); 
      //  }
      //});
    }

    Sphere.prototype.update = function(interp) {
      World.prototype.update.call(this, interp);
    }

    function Circle(sphere, tilt, rotation) {
      BaseEntity.prototype.constructor.call(this);
      this.sphere = sphere;
      this.tilt = tilt;
      this.initial_tilt = tilt;
      this.tilt_velocity = 0;
      this.rotation = rotation;
      this.rotation_velocity = 0;
      this.initial_velocity = 0;
      this.width = Math.PI / 100;
      this.color = "rgb(255,255,255)";
      this.color_int = [255,255,255];
      this.alpha = 0;
      this.my_div = "";
      this.is_active = true;
      this.sphere_index = -1;
      this.has_mouse = false;

      // TODO: Inactive circles should not update 
      this.addUpdater(function(interp) {
        this.tilt += this.tilt_velocity * interp;
        this.tilt %= Math.PI * 2;

        this.rotation += this.rotation_velocity * interp;
        this.rotation %= Math.PI;

        // The following will ensure that negative rotations are made positive
        // and is probably faster than branching logic (an unsupported assumption)
        this.rotation += Math.PI;
        this.rotation %= Math.PI;
      });
    }
    Circle.prototype.__proto__ = BaseEntity.prototype;


    Circle.prototype.bezier_offset_x = function() {
      return -this.sphere.radius * 2 * 0.03;
    }

    Circle.prototype.associateWithDiv = function(the_div) {
        this.my_div = the_div;
        the_div.attr('circle_id', this.sphere_index);
        the_div.bind({
            mouseenter: function() {
                var circle_id = $(this).attr('circle_id');
                var circle = window.sphere.circles[circle_id];
                circle.sphere.deactivateCircles();
                circle.has_mouse = true;
                circle.is_active = true;
                // circle.removeAllUpdaters();
                // circle.tween(undefined, { 'tilt': circle.initial_tilt, 'rotation': Math.PI/2, 'alpha': 1 }, undefined, ((new Date()).getTime() + 500));
            },
            mouseleave: function() {
                var circle_id = $(this).attr('circle_id');
                var circle = window.sphere.circles[circle_id];
                //circle.has_mouse = false;
                //circle.rotation_velocity = circle.initial_velocity;
                //circle.sphere.activateCircles();
                // circle.removeAllUpdaters();
                // circle.tween(undefined, { 'rotation': 0, 'alpha': 0, 'tilt': 0 }, undefined, ((new Date()).getTime() + 1000));
            }
        });
    }

    Circle.prototype.bezier_offset_y = function(offset) {
      offset = (offset === undefined) ? 0 : offset;
      return this.sphere.radius * 4.0 / 3.0 * Math.cos(this.rotation + offset);
    }

    Circle.prototype.draw = function(context, otherside) {
      //Just a straight bezier curve from one side to the other gives the circle a
      //flat look.  To add width to make the circle look like a ring that is fatter
      //when the sphere is "closer" to the viewer and thinner as it wraps around
      //the sphere, two bezier curves are drawn. One with slightly more rotation
      //than the circle itself and one with less.  Then these two bezier curves are
      //filled in.  However, while providing width to the circle, this still leaves
      //the ring coming to a point at the edges which doesn't look good. So the
      //starting and ending points of the two bezier curves are also spread
      //according to the width to leave the circle with some thickness at the
      //edges.

      if (this.alpha == 0) return;

      //hacky way of transitioning the ring to the other side of the sphere
      if (Math.abs(Math.PI - this.rotation % Math.PI) < 0.10 && ! otherside) {
        
        //Draw the circle on both sides when near the edges
        this.rotation -= Math.PI;
        this.draw(context, true);
        this.rotation += Math.PI

        //Draw a couple arcs to connect the two circles
        context.save();
        context.strokeStyle = this.color;
        context.lineWidth = 0.5;
        context.globalAlpha = this.alpha;
        context.translate(this.sphere.x, this.sphere.y)
        context.rotate(this.tilt);
        var halfpi = Math.PI / 2;
        var fill = Math.PI / 15;
        var start = halfpi - fill;
        var end = halfpi + fill;

        context.beginPath();
        context.arc(0, 0, this.sphere.radius * 0.995, start, end, false);
        context.stroke();

        start += Math.PI;
        end += Math.PI;
        context.beginPath();
        context.arc(0, 0, this.sphere.radius * 0.997, start, end, false);
        context.stroke();

        context.restore();
      }

      context.save();
      context.fillStyle = this.color;
      context.globalAlpha = this.alpha;

      //Reduce the width if the circle is near the edge and we're not drawing
      //circles behind the sphere
      var width = this.width;
      var new_width = Math.abs(Math.PI - (this.rotation % Math.PI));
      if (new_width < this.width) {
        width = new_width;
      }

      //if the circle is "behind" the sphere (rotation > Math.PI), reduce the width
      //to make it look farther away. Also, make the width negative so the yoffset
      //equation doesn't criss-cross the two bezier curves.
      var center_width;
      if (Math.abs(Math.floor(this.rotation / Math.PI) % 2) === 1) {
        center_width = this.width * -1 / 4.0;
      }
      else {
        center_width = this.width * 2;
      }

      //for the bezier curve control points that emulate an ellipse
      //the first bezier curve will have slightly less rotation, making it flatter
      //TODO: this equation is used twice, abstract
      var xoffset = this.bezier_offset_x();
      var yoffset = this.bezier_offset_y(-center_width / 2);

      //make the math below easier by moving the 0,0 to the center of the sphere
      context.translate(this.sphere.x, this.sphere.y)

      //make the math easier by drawing a bezier curve straight left to right
      //move the starting point of the first bezier curve down half the width
      context.rotate(this.tilt + (Math.PI / 2) - (width / 2));

      context.beginPath()
      context.moveTo(-this.sphere.radius, 0);
      //if the canvas wasn't rotated, the bezier curve would cross from the
      //slightly higher starting point set with the above rotation down across
      //to a lower point.  By rotating the canvas the width of the circle, it keeps
      //not just the start, but the end point lower as well.
      context.rotate(width);
      context.bezierCurveTo(
        -this.sphere.radius - xoffset, yoffset,
        this.sphere.radius + xoffset, yoffset,
        this.sphere.radius, 0
      );

      //The next bezier curve will have a little more rotation, making it arc more
      yoffset = this.bezier_offset_y(center_width / 2);

      //Rotate, move the line up to the new 3 o'clock position, then rotate again
      //so that the point that we move to when doing the bezier curve is also
      //higher up, and not straight across the sphere.
      context.rotate(-width);
      context.lineTo(this.sphere.radius, 0)
      context.rotate(width);
      context.bezierCurveTo(
        this.sphere.radius + xoffset, yoffset,
        -this.sphere.radius - xoffset, yoffset,
        -this.sphere.radius, 0
      );

      context.fill();
      context.restore();
      return;
    }

    Circle.prototype.update = function(interp) {
      interp = interp === undefined ? 0.03 : interp;
      BaseEntity.prototype.update.call(this, interp);
    }

    return {
        Circle: Circle,
        Sphere: Sphere
    }
});
