property total

on new me
  total = 0
  return me
end

on accumulate me, n
  total = total + n
  return total
end

on classify me, n
  if n > 10 then
    return "big"
  else
    return "small"
  end if
end

on sumTo me, n
  s = 0
  repeat with i = 1 to n
    s = s + i
  end repeat
  return s
end

on describe me, who, score
  return who && "scored" && string(score)
end

on firstOffset me, needle, hay
  return offset(needle, hay)
end

on drain me, n
  hits = 0
  repeat while n > 0
    n = n - 1
    hits = hits + 1
  end repeat
  return hits
end
