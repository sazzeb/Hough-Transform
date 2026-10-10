result = 2 + 2;
assert(result == 4);
disp("MATLAB works in VS Code");

figure('Visible', 'on', 'WindowStyle', 'normal');
plot(1:5, [1 4 9 16 25], '-o');
title('MATLAB Plot Test');
xlabel('X');
ylabel('Y');
grid on;
drawnow;
shg;