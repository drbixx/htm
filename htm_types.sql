CREATE OR REPLACE TYPE HTM_NUMBER_LIST AS TABLE OF NUMBER;
/

CREATE OR REPLACE TYPE HTM_VECTOR AS OBJECT (
  x NUMBER,
  y NUMBER,
  z NUMBER,

  CONSTRUCTOR FUNCTION HTM_VECTOR(x_val NUMBER, y_val NUMBER, z_val NUMBER) RETURN SELF AS RESULT,
  CONSTRUCTOR FUNCTION HTM_VECTOR(ra NUMBER, dec NUMBER) RETURN SELF AS RESULT,

  MEMBER FUNCTION magnitude RETURN NUMBER,
  MEMBER PROCEDURE normalize,
  MEMBER FUNCTION dot_product(v HTM_VECTOR) RETURN NUMBER,
  MEMBER FUNCTION cross_product(v HTM_VECTOR) RETURN HTM_VECTOR,
  MEMBER FUNCTION to_string RETURN VARCHAR2
);
/

CREATE OR REPLACE TYPE BODY HTM_VECTOR AS
  CONSTRUCTOR FUNCTION HTM_VECTOR(x_val NUMBER, y_val NUMBER, z_val NUMBER) RETURN SELF AS RESULT IS
  BEGIN
    SELF.x := x_val;
    SELF.y := y_val;
    SELF.z := z_val;
    RETURN;
  END;

  CONSTRUCTOR FUNCTION HTM_VECTOR(ra NUMBER, dec NUMBER) RETURN SELF AS RESULT IS
    ra_rad NUMBER;
    dec_rad NUMBER;
    cd NUMBER;
  BEGIN
    dec_rad := dec * HTM_UTILITIES.gPr; -- Use gPr from the HTM_UTILITIES package
    ra_rad  := ra * HTM_UTILITIES.gPr;  -- Use gPr from the HTM_UTILITIES package
    cd      := COS(dec_rad);

    SELF.x  := COS(ra_rad) * cd;
    SELF.y  := SIN(ra_rad) * cd;
    SELF.z  := SIN(dec_rad);
    RETURN;
  END;

  MEMBER FUNCTION magnitude RETURN NUMBER IS
  BEGIN
    RETURN SQRT(SELF.x*SELF.x + SELF.y*SELF.y + SELF.z*SELF.z);
  END;

  MEMBER PROCEDURE normalize IS
    mag NUMBER;
  BEGIN
    mag := SELF.magnitude(); -- Call the previously defined magnitude function

    IF mag > HTM_UTILITIES.gEpsilon THEN -- Use gEpsilon from HTM_UTILITIES
      SELF.x := SELF.x / mag;
      SELF.y := SELF.y / mag;
      SELF.z := SELF.z / mag;
    END IF;
    -- If mag is too small, the vector is considered a zero vector or too small to normalize reliably.
    -- Depending on requirements, an exception could be raised or it could be left as is.
    -- For now, it's left as is if magnitude is not greater than gEpsilon.
  END;

  MEMBER FUNCTION dot_product(v HTM_VECTOR) RETURN NUMBER IS
  BEGIN
    RETURN SELF.x * v.x + SELF.y * v.y + SELF.z * v.z;
  END;

  MEMBER FUNCTION cross_product(v HTM_VECTOR) RETURN HTM_VECTOR IS
    res_x NUMBER;
    res_y NUMBER;
    res_z NUMBER;
  BEGIN
    res_x := SELF.y * v.z - v.y * SELF.z;
    res_y := SELF.z * v.x - SELF.x * v.z; -- SELF.z*v.x - v.z*SELF.x in C++
    res_z := SELF.x * v.y - v.x * SELF.y;
    RETURN HTM_VECTOR(res_x, res_y, res_z);
  END;

  MEMBER FUNCTION to_string RETURN VARCHAR2 IS
  BEGIN
    RETURN '(' || SELF.x || ', ' || SELF.y || ', ' || SELF.z || ')';
  END;
END;
/

CREATE OR REPLACE TYPE HTM_VERTEX_LIST AS TABLE OF HTM_VECTOR;
/

CREATE OR REPLACE TYPE HTM_ID_RANGE AS OBJECT (
  low_id NUMBER,
  high_id NUMBER,

  CONSTRUCTOR FUNCTION HTM_ID_RANGE(l_id NUMBER, h_id NUMBER) RETURN SELF AS RESULT
);
/

CREATE OR REPLACE TYPE BODY HTM_ID_RANGE AS
  CONSTRUCTOR FUNCTION HTM_ID_RANGE(l_id NUMBER, h_id NUMBER) RETURN SELF AS RESULT IS
  BEGIN
    SELF.low_id := l_id;
    SELF.high_id := h_id;
    RETURN;
  END;
END;
/

CREATE OR REPLACE TYPE HTM_ID_RANGE_LIST AS TABLE OF HTM_ID_RANGE;
/

CREATE OR REPLACE TYPE HTM_NODE AS OBJECT (
  node_id NUMBER,
  parent_id NUMBER,
  level_num NUMBER,
  is_leaf NUMBER, -- 0 or 1
  children_ids HTM_NUMBER_LIST,
  v_ids HTM_NUMBER_LIST,
  w_ids HTM_NUMBER_LIST,

  CONSTRUCTOR FUNCTION HTM_NODE(
    p_node_id NUMBER,
    p_parent_id NUMBER,
    p_level_num NUMBER,
    p_is_leaf NUMBER,
    p_children_ids HTM_NUMBER_LIST,
    p_v_ids HTM_NUMBER_LIST,
    p_w_ids HTM_NUMBER_LIST DEFAULT NULL
  ) RETURN SELF AS RESULT
);
/

CREATE OR REPLACE TYPE BODY HTM_NODE AS
  CONSTRUCTOR FUNCTION HTM_NODE(
    p_node_id NUMBER,
    p_parent_id NUMBER,
    p_level_num NUMBER,
    p_is_leaf NUMBER,
    p_children_ids HTM_NUMBER_LIST,
    p_v_ids HTM_NUMBER_LIST,
    p_w_ids HTM_NUMBER_LIST DEFAULT NULL
  ) RETURN SELF AS RESULT IS
  BEGIN
    SELF.node_id := p_node_id;
    SELF.parent_id := p_parent_id;
    SELF.level_num := p_level_num;
    SELF.is_leaf := p_is_leaf;
    SELF.children_ids := p_children_ids;
    SELF.v_ids := p_v_ids;
    SELF.w_ids := p_w_ids;
    RETURN;
  END;
END;
/

CREATE OR REPLACE TYPE HTM_NODE_LIST AS TABLE OF HTM_NODE;
/

CREATE OR REPLACE TYPE HTM_LAYER_INFO AS OBJECT (
  level_num NUMBER,
  n_nodes NUMBER,
  n_vertices NUMBER,
  n_edges NUMBER,
  first_node_id NUMBER,
  first_vertex_id NUMBER,

  CONSTRUCTOR FUNCTION HTM_LAYER_INFO(
    p_level_num NUMBER,
    p_n_nodes NUMBER,
    p_n_vertices NUMBER,
    p_n_edges NUMBER,
    p_first_node_id NUMBER,
    p_first_vertex_id NUMBER
  ) RETURN SELF AS RESULT
);
/

CREATE OR REPLACE TYPE BODY HTM_LAYER_INFO AS
  CONSTRUCTOR FUNCTION HTM_LAYER_INFO(
    p_level_num NUMBER,
    p_n_nodes NUMBER,
    p_n_vertices NUMBER,
    p_n_edges NUMBER,
    p_first_node_id NUMBER,
    p_first_vertex_id NUMBER
  ) RETURN SELF AS RESULT IS
  BEGIN
    SELF.level_num := p_level_num;
    SELF.n_nodes := p_n_nodes;
    SELF.n_vertices := p_n_vertices;
    SELF.n_edges := p_n_edges;
    SELF.first_node_id := p_first_node_id;
    SELF.first_vertex_id := p_first_vertex_id;
    RETURN;
  END;
END;
/

CREATE OR REPLACE TYPE HTM_LAYER_LIST AS TABLE OF HTM_LAYER_INFO;
/
