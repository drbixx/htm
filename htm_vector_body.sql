CREATE OR REPLACE TYPE BODY HTM_VECTOR AS
  CONSTRUCTOR FUNCTION HTM_VECTOR(x_val NUMBER, y_val NUMBER, z_val NUMBER) RETURN SELF AS RESULT IS
  BEGIN
    SELF.x := x_val;
    SELF.y := y_val;
    SELF.z := z_val;
    RETURN;
  END;

  CONSTRUCTOR FUNCTION HTM_VECTOR(ra NUMBER, dec NUMBER) RETURN SELF AS RESULT IS
    c_pi CONSTANT NUMBER := ACOS(-1);
    phi NUMBER;
    theta NUMBER;
  BEGIN
    phi := ra * (c_pi / 180.0);
    theta := (90.0 - dec) * (c_pi / 180.0);

    SELF.x := SIN(theta) * COS(phi);
    SELF.y := SIN(theta) * SIN(phi);
    SELF.z := COS(theta);
    RETURN;
  END;

  MEMBER FUNCTION magnitude RETURN NUMBER IS
  BEGIN
    RETURN SQRT(SELF.x*SELF.x + SELF.y*SELF.y + SELF.z*SELF.z);
  END;

  MEMBER PROCEDURE normalize IS
    mag NUMBER;
  BEGIN
    mag := SELF.magnitude();
    IF mag > 0 THEN
      SELF.x := SELF.x / mag;
      SELF.y := SELF.y / mag;
      SELF.z := SELF.z / mag;
    END IF;
    -- Decide on error handling if mag is 0. For now, it leaves the vector as is.
  END;

  MEMBER FUNCTION dot_product(v HTM_VECTOR) RETURN NUMBER IS
  BEGIN
    RETURN SELF.x*v.x + SELF.y*v.y + SELF.z*v.z;
  END;

  MEMBER FUNCTION cross_product(v HTM_VECTOR) RETURN HTM_VECTOR IS
    new_x NUMBER;
    new_y NUMBER;
    new_z NUMBER;
  BEGIN
    new_x := SELF.y*v.z - SELF.z*v.y;
    new_y := SELF.z*v.x - SELF.x*v.z;
    new_z := SELF.x*v.y - SELF.y*v.x;
    RETURN HTM_VECTOR(new_x, new_y, new_z);
  END;

  MEMBER FUNCTION to_string RETURN VARCHAR2 IS
  BEGIN
    RETURN '(' || TO_CHAR(SELF.x) || ', ' || TO_CHAR(SELF.y) || ', ' || TO_CHAR(SELF.z) || ')';
  END;
END;
/
