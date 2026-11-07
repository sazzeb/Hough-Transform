
classdef HaarTransform
    % Convert image blocks to and from Haar wavelet values.
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
            % Turn 2-by-2 pixel blocks into Haar wavelet values.
            validateattributes(blocks, {'numeric'}, ...
                {'2d', 'ncols', 4, 'real', 'finite'});

            coefficients = double(blocks) * HaarTransform.Matrix.';
        end

        function blocks = inverse(coefficients)
            % Turn Haar wavelet values back into pixel blocks.
            validateattributes(coefficients, {'numeric'}, ...
                {'2d', 'ncols', 4, 'real', 'finite'});

            blocks = double(coefficients) * HaarTransform.Matrix;
        end
    end
end
