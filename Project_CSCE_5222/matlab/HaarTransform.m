
classdef HaarTransform
    properties (Constant, Access = private)
        Matrix = [ ...
            1  1  1  1; ...
            1 -1  1 -1; ...
            1  1 -1 -1; ...
            1 -1 -1  1 ...
            ] / 2
    end

    methods (Static)
        function coefficients = forward(blocks)
            validateattributes(blocks, {'numeric'}, ...
                {'2d', 'ncols', 4, 'real', 'finite'});

            coefficients = double(blocks) * HaarTransform.Matrix.';
        end

        function blocks = inverse(coefficients)
            validateattributes(coefficients, {'numeric'}, ...
                {'2d', 'ncols', 4, 'real', 'finite'});

            blocks = double(coefficients) * HaarTransform.Matrix;
        end
    end
end
