module Prawn
  module Svg
    class Parser::Path
      # Raised if the SVG path cannot be parsed.
      InvalidError = Class.new(StandardError)

      #
      # Parses an SVG path and returns a Prawn-compatible call tree.
      #
      def parse(data)
        cmd = values = nil
        value = ""
        @subpath_initial_point = @last_point = @arc_centre = nil
        @previous_control_point = @previous_quadratic_control_point = nil
        @calls = []

        data.each_char do |c|
          if c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z'
            # if drawing an arc, need to get centre point from 'L' in data
            # not tested for 'a', only 'A'
            if c == 'A'
              key, x, y = data.scan(/(L)(\s+\d+)(\s+\d+)/).first
              raise InvalidError, "Line to value must be specified in SVG path data containing command 'A'" if key.nil?
              @arc_centre = [x.to_f, y.to_f]
            end

            values << value.to_f if value != ""
            run_path_command(cmd, values) if cmd
            cmd = c
            values = []
            value = ""
          elsif c >= '0' && c <= '9' || c == '.' || (c == "-" && value == "")
            unless cmd
              raise InvalidError, "Numerical value specified before character command in SVG path data"
            end
            value << c
          elsif c == ' ' || c == "\t" || c == "\r" || c == "\n" || c == ","
            if value != ""
              values << value.to_f
              value = ""
            end
          elsif c == '-'
            values << value.to_f
            value = c
          else
            raise InvalidError, "Invalid character '#{c}' in SVG path data"
          end
        end

        values << value.to_f if value != ""
        run_path_command(cmd, values) if cmd

        @calls
      end


      private
      def run_path_command(command, values)
        upcase_command = command.upcase
        relative = command != upcase_command

        case upcase_command
        when 'M' # moveto
          x = values.shift
          y = values.shift

          if relative && @last_point
            x += @last_point.first
            y += @last_point.last
          end

          @last_point = @subpath_initial_point = [x, y]
          @calls << ["move_to", @last_point]

          return run_path_command('L', values) if values.any?
        when 'A'
          while values.any?
            # SVG Specifications for eliptical arc curve commands
            # Of the four candidate arc sweeps, two will represent an arc sweep of greater than or equal to 180 degrees (the "large-arc"),
            # and two will represent an arc sweep of less than or equal to 180 degrees (the "small-arc")
            # if large-arc-flag is '1', then one of the two larger arc sweeps will be chosen; otherwise, if large-arc-flag is '0', one of the smaller arc sweeps will be chosen
            # If sweep-flag is '1', then the arc will be drawn in a "positive-angle" direction
            # (i.e., the ellipse formula x=cx+rx*cos(theta) and y=cy+ry*sin(theta) is evaluated such that theta starts at an angle corresponding to the current point
            # and increases positively until the arc reaches (x,y)).
            # A value of 0 causes the arc to be drawn in a "negative-angle" direction (i.e., theta starts at an angle value corresponding to the current point
            # and decreases until the arc reaches (x,y)).

            rx, ry, x_axis_rotation, large_arc_flag, sweep_flag, x, y = (1..7).collect {values.shift}
            centre_point = @arc_centre

            # skip if the radius is 0
            unless rx == 0
              case [large_arc_flag, sweep_flag]
              when [0, 1] # arc sweep is less than 180 and in clockwise direction
                # p "arc sweep is less than 180 and in clockwise direction"
                arc_start_point = [x, y]
                arc_end_point = @last_point
                x = arc_start_point.first - centre_point.first
                y = arc_end_point.first - centre_point.first
                flip_x = arc_start_point.last > centre_point.last ? -1 : 1
                flip_y = arc_end_point.last > centre_point.last ? -1 : 1

                start_angle = Math.acos(x/rx) * 180/Math::PI * flip_x
                end_angle = Math.acos(y/rx) * 180/Math::PI * flip_y

                # edge case, as we always draw anti-clockwise, reverse angles if required
                start_angle, end_angle = [end_angle, start_angle] if x < y
              when [1, 1] # arc sweep is more than 180 and in clockwise direction
                arc_start_point = [x, y]
                arc_end_point = @last_point

                x = arc_start_point.first - centre_point.first
                y = arc_end_point.first - centre_point.first
                x = x * -1 if arc_start_point.first < centre_point.first && arc_start_point.last > centre_point.last
                y = y * -1 if arc_end_point.first < centre_point.first
                flip_x = arc_start_point.last > centre_point.last ? 180 : 0
                flip_y = arc_end_point.last > centre_point.last && arc_end_point.last < centre_point.last ? 180 : 0

                start_angle = Math.acos(x/rx) * 180/Math::PI + flip_x
                end_angle = Math.acos(y/rx) * 180/Math::PI + flip_y
              when [0, 0] # arc sweep is less than 180 and in anti-clockwise direction
                arc_start_point = @last_point
                arc_end_point = [x, y]

                x = arc_start_point.first + centre_point.first
                y = arc_end_point.first + centre_point.first
                flip_x = arc_start_point.last > centre_point.last ? -1 : 1
                flip_y = arc_end_point.last > centre_point.last ? -1 : 1

                start_angle = Math.acos(x/rx) * 180/Math::PI * flip_x
                end_angle = Math.acos(y/rx) * 180/Math::PI * flip_y
              when [1, 0] # arc sweep is more than 180 and in anti-clockwise direction
                arc_start_point = @last_point
                arc_end_point = [x, y]

                flip_x = arc_start_point.last > centre_point.last ? 180 : 0
                flip_y = arc_end_point.last > centre_point.last ? 180 : 0

                start_angle = Math.acos(x/rx) * 180/Math::PI + flip_x
                end_angle = Math.acos(y/rx) * 180/Math::PI + flip_y
              end

              angles = [start_angle, end_angle]

              @calls << ["pie_slice", [centre_point, rx, rx, angles].flatten]

            end
          end
        when 'Z' # closepath
          if @subpath_initial_point
            #@calls << ["line_to", @subpath_initial_point]
            @calls << ["close_path"]
            @last_point = @subpath_initial_point
          end

        when 'L' # lineto
          while values.any?
            x = values.shift
            y = values.shift
            if relative && @last_point
              x += @last_point.first
              y += @last_point.last
            end
            @last_point = [x, y]
            @calls << ["line_to", @last_point]
          end

        when 'H' # horizontal lineto
          while values.any?
            x = values.shift
            x += @last_point.first if relative && @last_point
            @last_point = [x, @last_point.last]
            @calls << ["line_to", @last_point]
          end

        when 'V' # vertical lineto
          while values.any?
            y = values.shift
            y += @last_point.last if relative && @last_point
            @last_point = [@last_point.first, y]
            @calls << ["line_to", @last_point]
          end

        when 'C' # curveto
          while values.any?
            x1, y1, x2, y2, x, y = (1..6).collect {values.shift}
            if relative && @last_point
              x += @last_point.first
              x1 += @last_point.first
              x2 += @last_point.first
              y += @last_point.last
              y1 += @last_point.last
              y2 += @last_point.last
            end

            @last_point = [x, y]
            @previous_control_point = [x2, y2]
            @calls << ["curve_to", [x, y, x1, y1, x2, y2].map {|i| i.round(2)} ]
          end

        when 'S' # shorthand/smooth curveto
          while values.any?
            x2, y2, x, y = (1..4).collect {values.shift}
            if relative && @last_point
              x += @last_point.first
              x2 += @last_point.first
              y += @last_point.last
              y2 += @last_point.last
            end

            if @previous_control_point
              x1 = 2 * @last_point.first - @previous_control_point.first
              y1 = 2 * @last_point.last - @previous_control_point.last
            else
              x1, y1 = @last_point
            end

            @last_point = [x, y]
            @previous_control_point = [x2, y2]
            @calls << ["curve_to", [x, y, x1, y1, x2, y2].map {|i| i.round(2)}]
          end

        when 'Q', 'T' # quadratic curveto
          while values.any?
            if shorthand = upcase_command == 'T'
              x, y = (1..2).collect {values.shift}
            else
              x1, y1, x, y = (1..4).collect {values.shift}
            end

            if relative && @last_point
              x += @last_point.first
              x1 += @last_point.first if x1
              y += @last_point.last
              y1 += @last_point.last if y1
            end

            if shorthand
              if @previous_quadratic_control_point
                x1 = 2 * @last_point.first - @previous_quadratic_control_point.first
                y1 = 2 * @last_point.last - @previous_quadratic_control_point.last
              else
                x1, y1 = @last_point
              end
            end

            # convert from quadratic to cubic
            cx1 = @last_point.first + (x1 - @last_point.first) * 2 / 3.0
            cy1 = @last_point.last + (y1 - @last_point.last) * 2 / 3.0
            cx2 = cx1 + (x - @last_point.first) / 3.0
            cy2 = cy1 + (y - @last_point.last) / 3.0

            @last_point = [x, y]
            @previous_quadratic_control_point = [x1, y1]
            @calls << ["curve_to", [x, y, cx1, cy1, cx2, cy2].map {|i| i.round(2)}]
          end

        end

        @previous_control_point = nil unless %w(C S).include?(upcase_command)
        @previous_quadratic_control_point = nil unless %w(Q T).include?(upcase_command)
      end
    end
  end
end
