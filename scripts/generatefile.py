import random
f = open('file.txt', 'w')
for _ in range(2 ** 20):
  f.write(random.choice(['a', 'b', '\n']))
f.close()