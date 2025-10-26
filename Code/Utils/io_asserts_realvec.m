function io_asserts_realvec(x)
% IO_ASSERTS_REALVEC  Validate real-valued numeric vector.
validateattributes(x, {'numeric'}, {'vector','nonempty','finite','real'}, mfilename, 'x');
end
