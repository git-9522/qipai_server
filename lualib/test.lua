require "preload"

print(tostring_r({1,2,3,4,5}))
print(tostring_r({ 1,2,3,key={1212},val = {1,2,3,4,{3,4,5,"6"}}}))

function test_info()
    local t = debug.getinfo(1,'nSltu')
    print(tostring_r(t))
end



test_info()
print(tostring_r(os.date('*t')))

function haha()
print(1,2,3)
print_r({1,2,3,45})
end

haha()
