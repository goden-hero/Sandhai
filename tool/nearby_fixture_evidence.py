"""Independent spherical fixture calculation (standard Python, no app imports).
Uses 3-D unit-vector cross/dot atan2 distance, independently of Dart Haversine.
"""
import json,math
EARTH_RADIUS=6371000.0

def destination(lat,lng,metres,bearing):
 a,o,b,d=map(float,(math.radians(lat),math.radians(lng),math.radians(bearing),metres/EARTH_RADIUS))
 y=math.asin(math.sin(a)*math.cos(d)+math.cos(a)*math.sin(d)*math.cos(b))
 x=o+math.atan2(math.sin(b)*math.sin(d)*math.cos(a),math.cos(d)-math.sin(a)*math.sin(y))
 return math.degrees(y),(math.degrees(x)+540)%360-180

def distance(a,b):
 def unit(p):
  lat,lng=map(math.radians,p);return (math.cos(lat)*math.cos(lng),math.cos(lat)*math.sin(lng),math.sin(lat))
 x,y=unit(a),unit(b);dot=sum(i*j for i,j in zip(x,y));cross=(x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0])
 return EARTH_RADIUS*math.atan2(math.sqrt(sum(v*v for v in cross)),dot)

if __name__=='__main__':
 rows=[]
 for metres,lat in [(4990,.044876148135344655),(5000,.044966080295936524),(5010,.045056012456528396)]:
  measured=distance((0,0),(lat,0));rows.append({'latitude':lat,'longitude':0,'targetMetres':metres,'vectorDistanceMetres':measured,'include':metres<=5000})
 print(json.dumps({'earthRadiusMetres':EARTH_RADIUS,'center':[0,0],'method':'atan2(norm(cross(unit vectors)), dot(unit vectors))','boundaryFixtures':rows,'bearingFixtures':[{'bearing':b,'coordinate':destination(13.0276441,77.6129353,4990,b)} for b in range(0,360,45)]},indent=2))
